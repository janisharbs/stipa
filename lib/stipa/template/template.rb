require 'erb'
require 'json'

module Stipa
  # ERB template engine with layout support and Vue.js integration helpers.
  #
  # Usage:
  #   engine = Stipa::Template.new(views_dir: 'views')
  #   html   = engine.render('home', locals: { user: 'Alice' })
  #
  # With an explicit layout:
  #   html = engine.render('home', layout: 'layouts/admin')
  #
  # Without a layout (useful for partials / API fragments):
  #   html = engine.render('_row', locals: { item: obj }, layout: false)
  #
  # Directory conventions:
  #   views/
  #     layouts/
  #       application.html.erb   ← default layout
  #     home.html.erb
  #     users/
  #       show.html.erb
  #     _sidebar.html.erb        ← partials start with _
  class Template
    attr_reader :views_dir

    def initialize(views_dir:)
      @views_dir = File.expand_path(views_dir)
    end

    # Render a template, optionally wrapped in a layout.
    #
    # template - name like 'home', 'users/show', or 'home.html.erb'
    # locals   - Hash of variables made available inside the template
    # layout   - :default  → auto-detect views/layouts/application.html.erb
    #            a String  → explicit layout name (same resolution as template)
    #            false     → no layout
    def render(template, locals: {}, layout: :default)
      ctx = ViewContext.new(self)
      locals.each { |k, v| ctx._set_local(k, v) }

      content = render_file(resolve(template), ctx)

      layout_path = resolve_layout(layout)
      if layout_path && File.exist?(layout_path)
        ctx._set_content(content)
        render_file(layout_path, ctx)
      else
        content
      end
    end

    private

    def render_file(path, ctx)
      template = ERB.new(File.read(path), trim_mode: '-')
      template.result(ctx._binding)
    rescue Errno::ENOENT => e
      raise "Template not found: #{path}"
    end

    def resolve(name)
      # If it already ends with .erb, use it as-is; otherwise add .html.erb
      name = "#{name}.html.erb" unless name.end_with?('.erb')
      File.join(@views_dir, name)
    end

    def resolve_layout(layout)
      return nil if layout == false
      name = layout == :default ? 'layouts/application.html.erb' : "#{layout}.html.erb"
      File.join(@views_dir, name)
    end
  end

  # -------------------------------------------------------------------------
  # View Context: the binding for ERB templates
  # -------------------------------------------------------------------------

  # The context object that becomes `self` inside every template.
  # Includes helpers for rendering, HTML escaping, and Vue integration.
  class ViewContext
    def initialize(engine)
      @engine = engine
      @_blocks = {}
    end

    # -------------------------------------------------------------------------
    # General helpers
    # -------------------------------------------------------------------------

    # Render a template (same engine, layout: false by default).
    # Useful for partials; pass layout: :default if you want to wrap it.
    def render_template(name, locals: {})
      @engine.render(name, locals: locals, layout: false)
    end

    # HTML-escape a value. Use this in attributes or when interpolating
    # untrusted user input inside text content.
    #
    #   <div class="<%= escape_html(user.css_class) %>">
    #
    # Or use the alias:
    #
    #   <div class="<%= h(user.css_class) %>">
    def h(value)
      ERB::Util.html_escape(value.to_s)
    end
    alias escape_html h

    # -------------------------------------------------------------------------
    # Vue.js helpers
    # -------------------------------------------------------------------------

    # Emit a Vue 3 component mount point.
    #
    # The Stīpa Vue bootstrapper (stipa-vue.js) picks up all elements with
    # data-vue-component and mounts the corresponding registered component,
    # passing data-props as the component's initial props.
    #
    # ERB:
    #   <%= vue_component("Counter", props: { initial: 5 }) %>
    #   <%= vue_component("SearchBox", props: { q: params[:q] }, class: "mt-4") %>
    #
    # Rendered HTML:
    #   <div data-vue-component="Counter" data-props="{&quot;initial&quot;:5}"></div>
    #
    # Options:
    #   props:  Hash passed as JSON to the component (default {})
    #   tag:    HTML wrapper element (default 'div')
    #   Any other keyword args become HTML attributes on the wrapper element.
    def vue_component(name, props: {}, tag: 'div', **html_attrs)
      attr_parts = html_attrs.map { |k, v| %(#{k}="#{h(v)}") }
      attr_str   = attr_parts.empty? ? '' : " #{attr_parts.join(' ')}"
      props_json = h(props.to_json)
      %(<#{tag} data-vue-component="#{h(name)}" data-props="#{props_json}"#{attr_str}></#{tag}>)
    end

    # Include Vue 3 from a CDN (or a local path you serve).
    #
    #   <%= vue_script %>                          → unpkg, production build
    #   <%= vue_script(version: '3.4.21') %>       → pin a specific version
    #   <%= vue_script(dev: true) %>               → development build (warnings)
    #   <%= vue_script(src: '/vendor/vue.js') %>   → self-hosted
    def vue_script(src: nil, version: '3', dev: false)
      unless src
        build = dev ? 'vue.global.js' : 'vue.global.prod.js'
        src   = "https://unpkg.com/vue@#{version}/dist/#{build}"
      end
      %(<script src="#{src}"></script>)
    end

    # Include the Stīpa Vue bootstrapper.
    # This script auto-discovers vue_component mount points and mounts them.
    # Must appear AFTER vue_script and AFTER any component registrations.
    #
    #   <%= stipa_vue_bootstrap %>
    def stipa_vue_bootstrap(src: '/stipa-vue.js')
      %(<script type="module" src="#{src}"></script>)
    end

    # Include one or more JavaScript files.
    #   <%= javascript_tag '/app.js' %>
    #   <%= javascript_tag '/a.js', '/b.js', type: 'module' %>
    def javascript_tag(*srcs, type: nil, **attrs)
      extra     = attrs.map { |k, v| %( #{k}="#{h(v)}") }.join
      type_attr = type ? %( type="#{h(type)}") : ''
      srcs.map { |src| %(<script src="#{h(src)}"#{type_attr}#{extra}></script>) }.join("\n")
    end

    # Include one or more stylesheets.
    #   <%= stylesheet_tag '/app.css' %>
    #   <%= stylesheet_tag '/reset.css', '/app.css' %>
    def stylesheet_tag(*hrefs, **attrs)
      extra = attrs.map { |k, v| %( #{k}="#{h(v)}") }.join
      hrefs.map { |href| %(<link rel="stylesheet" href="#{h(href)}"#{extra}>) }.join("\n")
    end

    # -------------------------------------------------------------------------
    # Private: template/layout machinery
    # -------------------------------------------------------------------------

    # Internal: inject a local variable as a method on this context.
    def _set_local(name, value)
      define_singleton_method(name) { value }
    end

    # Internal: store the inner-page HTML for the layout's `yield`.
    def _set_content(html)
      @_layout_content = html
    end

    # Internal: expose binding for ERB.
    def _binding
      binding
    end

    # Called inside a layout template to render the inner page content.
    #
    # Use one of these in your layout:
    #   <body><%= content %></body>
    #   <body><%= yield_content %></body>
    #
    # (Plain ERB `yield` is a Ruby keyword and cannot be used here.)
    def content
      @_layout_content
    end
    alias yield_content content

    # Named content blocks — store content from a page, render in the layout.
    #
    # Page:   <% content_for :title do %>Home<% end %>
    # Layout: <title><%= content_for(:title) %></title>
    def content_for(section = nil, &block)
      return @_blocks[section] if section && !block
      @_blocks[section] = block.call if section && block
    end

    # Render a partial from within a template.
    # Partials follow the Rails convention of a leading underscore on disk,
    # but you refer to them without it.
    #
    #   <%= render 'sidebar' %>                         → views/_sidebar.html.erb
    #   <%= render 'users/row', locals: { u: user } %> → views/users/_row.html.erb
    def render(partial, locals: {})
      name = if partial.include?('/')
               partial.sub(%r{([^/]+)\z}, '_\1')
             else
               "_#{partial}"
             end
      @engine.render(name, locals: locals, layout: false)
    end
  end
end
