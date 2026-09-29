// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import { postMagicLink } from "cyvasse/sign_in"

// The sign-in modal (modals/_auth) calls it from Alpine.
window.postMagicLink = postMagicLink
