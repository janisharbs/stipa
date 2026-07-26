<p align="center">
  <img src="media/logo.png" alt="Stīpa" width="80">
</p>

<h1 align="center">Stīpa</h1>
<p align="center">Minimal, production-ready HTTP framework for Ruby — zero dependencies, stdlib only.</p>

---

## Features

- **Zero dependencies** — pure Ruby stdlib (`socket`, `thread`, `erb`, `json`, `securerandom`)
- **HTTP/1.1** keep-alive, `SO_REUSEPORT`, `TCP_NODELAY`
- **Thread pool** with bounded queue and graceful shutdown
- **Middleware stack** compiled once at startup — zero per-request overhead
- **ERB template engine** with layouts, partials, and Vue 3 island helpers
- **CLI generator** — `stipa new myapp` scaffolds a full MVC app with Vue + TypeScript
- **Database layer** — optional Sequel integration with migrations, models, and connection management

---

## Installation

```bash
gem install stipa
```

Or in a `Gemfile`:

```ruby
gem 'stipa'
```

---

## Quick start

```ruby
require 'stipa'

app = Stipa::App.new

app.get '/' do |_req, res|
  res.body = 'Hello, Stīpa!'
end

app.get '/health' do |_req, res|
  res.json(status: 'ok', version: Stipa::VERSION)
end

app.start(port: 3710)
```

```bash
ruby server.rb
# => Stīpa listening on 127.0.0.1:3710
```

---

## CLI

Generate a new MVC app with Vue 3 + TypeScript:

```bash
stipa new myapp          # Vue MVC (default)
stipa new myapp --vue    # same
stipa new myapp --api    # API-only, no views
```

Generated structure (`--vue`):

```
myapp/
├── server.rb                    # entry point
├── Gemfile
├── Rakefile                     # db:migrate, db:rollback, db:version
├── package.json                 # rollup + vue + typescript
├── rollup.config.js
├── tsconfig.json
├── app/
│   ├── config/
│   │   ├── database.rb          # DATABASE_URL, Sequel settings
│   │   └── routes.rb
│   ├── controllers/
│   ├── models/
│   │   └── application_model.rb # base model with Stipa::Model
│   ├── views/
│   └── components/              # Vue SFC source (.vue, .ts)
├── db/
│   └── migrate/                 # Sequel migrations
└── public/
    ├── stipa-vue.js
    ├── app.css
    └── components/              # Rollup compiled output
```

```bash
cd myapp
bundle install
npm install
npm run build                    # compile Vue components
bundle exec ruby server.rb
```

Hot reload during development:

```bash
STIPA_RELOAD=1 bundle exec ruby server.rb
```

The reloader watches all `.rb` files under the project root. When a change is saved it
restarts the process automatically. If the changed file has a syntax error the reloader
logs the problem and keeps watching — the process will not die on a bad save.

---

## Routing

Patterns are either exact strings or regular expressions. First match wins.

```ruby
app.get    '/posts',                        &handler
app.post   '/posts',                        &handler
app.put    %r{/posts/(?<id>\d+)},           &handler
app.patch  %r{/posts/(?<id>\d+)},           &handler
app.delete %r{/posts/(?<id>\d+)},           &handler
```

Named captures are available as `req.params`:

```ruby
app.get %r{/users/(?<id>\d+)} do |req, res|
  res.json(id: req.params[:id].to_i)
end
```

---

## Request & Response

```ruby
app.post '/echo' do |req, res|
  req.method          # => "POST"
  req.path            # => "/echo"
  req.query_string    # => "foo=bar"
  req.body            # => raw body string
  req['content-type'] # => "application/json" (case-insensitive)
  req.params          # => { id: "42" } (from named captures)

  res.status = 201
  res.body   = 'created'
  res['X-Custom'] = 'value'
  res.json(ok: true)  # sets body + Content-Type: application/json
end
```

---

## Middleware

```ruby
app.use Stipa::Middleware::RequestId          # mint/propagate X-Request-Id
app.use Stipa::Middleware::Timing            # append X-Response-Time
app.use Stipa::Middleware::Cors, origins: ['https://example.com']
app.use Stipa::Middleware::Static, root: 'public'
```

Custom middleware:

```ruby
# Class-based
class Auth
  def initialize(app)
    @app = app
  end

  def call(req, res)
    return res.tap { res.status = 401 } unless req['authorization']
    @app.call(req, res)
  end
end

app.use Auth

# Lambda-based
app.use ->(req, res, next_app) {
  puts "#{req.method} #{req.path}"
  next_app.call(req, res)
}
```

---

## MVC

### Routes

```ruby
# config/routes.rb
class Routes
  def self.draw(app) = new(app).draw

  def draw
    get  '/',      to: 'home#index'
    get  '/posts', to: 'posts#index'
    post '/posts', to: 'posts#create'
  end

  # ...
end
```

### Controllers

```ruby
class PostsController < ApplicationController
  def index
    render('posts/index', locals: { posts: Post.all })
  end

  def create
    post = Post.create(params.slice(:title, :body))
    redirect_to "/posts/#{post.id}"
  end
end
```

### Views (ERB)

```
views/
  layouts/
    application.html.erb   ← wraps every page
  posts/
    index.html.erb
    show.html.erb
    _form.html.erb         ← partial (underscore prefix)
```

```erb
<%# layouts/application.html.erb %>
<%= stylesheet_tag '/app.css' %>
<main><%= content %></main>

<%# posts/index.html.erb %>
<% posts.each do |post| %>
  <%= render 'posts/form', locals: { post: post } %>
<% end %>
```

---

## Vue 3 Islands

Mount interactive components anywhere inside ERB views — server renders the shell, Vue hydrates on the client.

**Layout:**

```erb
<%= vue_script %>
<%= stipa_vue_bootstrap %>

<script src="/components/Counter.js"></script>
<script>
  window.StipaVue.register('Counter', window.Counter)
</script>
```

**View:**

```erb
<%= vue_component('Counter', props: { initial: 0 }) %>
```

**Component** (`src/components/Counter.vue`):

```vue
<template>
  <button @click="n++">Clicked {{ n }} times</button>
</template>

<script lang="ts">
import { defineComponent, ref } from "vue";
export default defineComponent({
  props: { initial: { type: Number, default: 0 } },
  setup(props) {
    const n = ref(props.initial);
    return { n };
  },
});
</script>
```

Build: `npm run build` → outputs `public/components/Counter.js`.

---

## Server options

```ruby
app.start(
  host:              '127.0.0.1', # default; use '0.0.0.0' to bind all interfaces
  port:              3710,
  pool_size:         32,          # worker threads
  queue_depth:       64,          # max queued jobs before backpressure
  drain_timeout:     30,          # graceful shutdown wait (seconds)
  keepalive_timeout: 5,
  max_requests:      100,         # per connection
  max_body_size:     1_048_576,
  backpressure:      :drop,       # :drop (503) or :block
  log_level:         :info,
  reload:            false,       # or set STIPA_RELOAD=1 in the environment
)
```

Handles `SIGTERM` / `SIGINT` with graceful drain.

---

## Security notes

- **Bind address** — the default `host: '127.0.0.1'` exposes the server only on
  localhost. Set `host: '0.0.0.0'` (or the specific interface IP) when running behind a
  reverse proxy or in a container.
- **CORS** — `Middleware::Cors` never reflects an arbitrary `Origin` header back to the
  client. Wildcard config (`origins: ['*']`) sends the literal `*`; an explicit list
  only allows origins that are in the list.
- **Hot reload** — `STIPA_RELOAD=1` is intended for development only. Do not enable it
  in production.

---

## Database

Optional Sequel integration. Add to your Gemfile:

```ruby
gem 'sequel'
gem 'pg'          # or mysql2, sqlite3
```

Configure via `DATABASE_URL`:

```bash
# .env (development / test)
DATABASE_URL=postgres://user:password@localhost:5432/myapp
```

```ruby
require 'stipa/database'

Stipa::Database.connect!
DB = Stipa::Database.connection

# health check
Stipa::Database.healthy?  # => true

# transactions
Stipa::Database.transaction { DB[:posts].insert(title: 'Hello') }

# shutdown
Stipa::Database.disconnect!
```

### Migrations

```bash
rake db:migrate    # run pending migrations
rake db:rollback   # rollback last migration
rake db:version    # show current version
```

Create a migration:

```ruby
# db/migrate/002_create_comments.rb
Sequel.migration do
  change do
    create_table :comments do
      primary_key :id
      foreign_key :post_id, null: false
      String :body, text: true
      DateTime :created_at, null: false
      DateTime :updated_at, null: false
    end
  end
end
```

---

## Models

Models use `Stipa::Model` — a set of Sequel plugins for common patterns:

```ruby
require 'stipa/model'

class Post < ApplicationModel
  # Included by default:
  #   - Timestamps    (created_at / updated_at)
  #   - UUID          (auto-generate UUID primary key)
  #   - SoftDelete    (deleted_at scoping)
  #   - Serialization (to_hash, to_json, from_json)

  plugin :validation_helpers

  def validate
    super
    validates_presence [:title]
    validates_unique   [:slug]
  end
end
```

### Standalone modules

Use individual modules without the full `Stipa::Model` bundle:

```ruby
class User < Sequel::Model
  include Stipa::Model::UUID
  include Stipa::Model::Pagination
end

# Pagination
result = User.paginate(page: 2, per_page: 10)
result[:records]     # => [#<User>, ...]
result[:total]       # => 150
result[:total_pages] # => 15

# Soft delete
user.soft_delete
user.deleted?       # => true
User.all            # => excludes soft-deleted
User.with_deleted   # => includes all
User.only_deleted   # => soft-deleted only
user.restore
```

---

## License

MIT
