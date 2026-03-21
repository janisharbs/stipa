/**
 * Stīpa Vue Bootstrapper (ES Module)
 *
 * Automatically mounts Vue 3 components declared with the ERB helper:
 *   <%= vue_component("Counter", props: { initial: 5 }) %>
 *
 * Which renders on the page as:
 *   <div data-vue-component="Counter" data-props='{"initial":5}'></div>
 *
 * Usage in your layout:
 *   <script type="importmap">{ "imports": { "vue": "/vendor/vue.esm-browser.prod.js" } }</script>
 *   <script type="module" src="/stipa-vue.js"></script>
 *   <script type="module" src="/app.js"></script>
 *
 * In app/main.ts, register components and call mount():
 *   const { StipaVue } = window
 *   StipaVue.register('Counter', Counter)
 *   StipaVue.mount()
 */
import { createApp } from 'vue'

const COMPONENT_ATTR = 'data-vue-component'
const PROPS_ATTR = 'data-props'
const MOUNTED_ATTR = 'data-stipa-vue-mounted'

const registry = {}
const mounted = []

const StipaVue = {
	register(name, component) {
		registry[name] = component
	},

	mount(root) {
		root = root || document

		// Prune stale entries for elements no longer in the DOM
		for (let i = mounted.length - 1; i >= 0; i--) {
			if (!document.contains(mounted[i].el)) {
				mounted.splice(i, 1)
			}
		}

		const selector = `[${COMPONENT_ATTR}]:not([${MOUNTED_ATTR}])`
		const elements = root.querySelectorAll(selector)

		elements.forEach((el) => {
			const name = el.getAttribute(COMPONENT_ATTR)
			const component = registry[name]

			if (!component) {
				console.warn(
					`[StipaVue] Component "${name}" is not registered. ` +
					`Call StipaVue.register("${name}", YourComponent) before calling StipaVue.mount().`
				)
				return
			}

			let props = {}
			const propsRaw = el.getAttribute(PROPS_ATTR)
			if (propsRaw) {
				try {
					props = JSON.parse(propsRaw)
				} catch (e) {
					console.error(`[StipaVue] Failed to parse props for "${name}":`, e)
				}
			}

			const app = createApp(component, props)
			app.mount(el)

			el.setAttribute(MOUNTED_ATTR, '1')
			mounted.push({ app, el })
		})
	},

	unmountAll() {
		mounted.forEach((entry) => {
			entry.app.unmount()
			entry.el.removeAttribute(MOUNTED_ATTR)
		})
		mounted.length = 0
	},
}

window.StipaVue = StipaVue
export { StipaVue }
export default StipaVue
