// Import and register all your controllers from the importmap via controllers/**/*_controller
//
// LAZILY: a controller's module is imported the first time its data-controller
// appears in the DOM (on load, or later via a Turbo visit or stream), never on
// a page that does not use it. Eager loading imported the whole game engine on
// the front door. The pages that mount a heavy controller preload its modules
// (config/importmap.rb, preload_modules), so the lazy import does not wait on
// a chain of fetches.
import { application } from "controllers/application"
import { lazyLoadControllersFrom } from "@hotwired/stimulus-loading"
lazyLoadControllersFrom("controllers", application)
