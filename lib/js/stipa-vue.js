/**
 * Stīpa Vue Bootstrapper
 *
 * Automatically mounts Vue 3 components declared with the ERB helper:
 *   <%= vue_component("Counter", props: { initial: 5 }) %>
 *
 * Which renders on the page as:
 *   <div data-vue-component="Counter" data-props='{"initial":5}'></div>
 *
 * Usage in your layout (after vue_script and component <script> tags):
 *   <%= stipa_vue_bootstrap %>
 *
 * Register components before DOMContentLoaded fires, or call StipaVue.mount()
 * manually after dynamic content is inserted.
 *
 * Example:
 *   <script type="module">
 *     import Counter from '/components/Counter.js'
 *     StipaVue.register('Counter', Counter)
 *   </script>
 *   <%= stipa_vue_bootstrap %>
 */
(() => {
	const COMPONENT_ATTR = "data-vue-component";
	const PROPS_ATTR = "data-props";
	const MOUNTED_ATTR = "data-stipa-vue-mounted";

	const registry = {};
	const mounted = [];

	const StipaVue = {
		register(name, component) {
			registry[name] = component;
		},

		mount(root) {
			root = root || document;

			if (typeof Vue === "undefined") {
				console.error(
					"[StipaVue] Vue is not defined. Make sure vue_script() appears before stipa_vue_bootstrap() in your layout.",
				);
				return;
			}

			// Prune stale entries for elements no longer in the DOM
			for (let i = mounted.length - 1; i >= 0; i--) {
				if (!document.contains(mounted[i].el)) {
					mounted.splice(i, 1);
				}
			}

			const selector = "[" + COMPONENT_ATTR + "]:not([" + MOUNTED_ATTR + "])";
			const elements = root.querySelectorAll(selector);

			elements.forEach((el) => {
				const name = el.getAttribute(COMPONENT_ATTR);
				const component = registry[name];

				if (!component) {
					console.warn(
						'[StipaVue] Component "' +
							name +
							'" is not registered. ' +
							'Call StipaVue.register("' +
							name +
							'", YourComponent) before the DOM loads.',
					);
					return;
				}

				let props = {};
				const propsRaw = el.getAttribute(PROPS_ATTR);
				if (propsRaw) {
					try {
						props = JSON.parse(propsRaw);
					} catch (e) {
						console.error('[StipaVue] Failed to parse props for "' + name + '":', e);
					}
				}

				const app = Vue.createApp(component, props);
				app.mount(el);

				el.setAttribute(MOUNTED_ATTR, "1");
				mounted.push({ app, el });
			});
		},

		unmountAll() {
			mounted.forEach((entry) => {
				entry.app.unmount();
				entry.el.removeAttribute(MOUNTED_ATTR);
			});
			mounted.length = 0;
		},
	};

	// DOMContentLoaded handles the synchronous registration pattern:
	// components registered via classic <script> tags before this event fires
	// will be mounted automatically. For async/module-based registration,
	// call StipaVue.mount() manually after registering.
	document.addEventListener("DOMContentLoaded", () => {
		StipaVue.mount();
	});

	window.StipaVue = StipaVue;
})();
