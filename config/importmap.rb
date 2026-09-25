# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
# The game engine (epic piece 4): plain ES modules that import each other as
# "cyvasse/<module>". test/javascript/support/importmap_hooks.mjs maps the
# same prefix for the node unit tests, so keep the two in step.
pin_all_from "app/javascript/cyvasse", under: "cyvasse"
