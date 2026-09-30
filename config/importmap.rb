# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"

# WHAT EACH PAGE PRELOADS. javascript_importmap_tags (the engine's head)
# emits a modulepreload for every pin whose preload is true, on every page.
# The game engine is most of the JavaScript, and the front door never runs it,
# so only what every page imports is true. The rest is preloaded by the pages
# that mount it: `preload` names a page group, and the page asks for its group
# with preload_modules (ApplicationHelper). Stimulus loads controllers lazily
# (controllers/index.js), so a module nobody preloads still loads the moment
# its data-controller appears; the preload only removes the import waterfall.
#
# Every file under the two directories below is pinned, as pin_all_from would
# (test/integration/module_preloads_test.rb holds that). pin_all_from itself
# cannot be used: one preload value covers its whole directory, and an explicit
# pin cannot override it (directories expand after pins). The cost: in
# development a NEW file is pinned only when this file is redrawn, so restart
# the server (or touch this file) after adding one. Locals, not constants:
# this file is instance_eval'd again on every redraw.
#
# The game engine (epic piece 4): plain ES modules that import each other as
# "cyvasse/<module>". test/javascript/support/importmap_hooks.mjs maps the
# same prefix for the node unit tests, so keep the two in step.
every_page = %w[controllers/application controllers cyvasse/sign_in].freeze
page_groups = {
  "controllers/home_gallery_controller" => "home",
  "controllers/live_seek_controller" => "seek",
  "cyvasse/seek_splash" => "seek",
  # A player's name fitted to its box: the splash and the match's versus card.
  "controllers/name_fit_controller" => %w[seek game],
  "cyvasse/name_fit" => %w[seek game]
}.freeze # anything else is the board: "game" (games/show, matches/show)

{ "controllers" => "app/javascript/controllers", "cyvasse" => "app/javascript/cyvasse" }.each do |under, dir|
  Dir.glob("**/*.js", base: Rails.root.join(dir)).sort.each do |file|
    # index.js answers to the bare prefix ("controllers"), as pin_all_from maps it.
    module_name = file.delete_suffix(".js")
    module_name = File.dirname(module_name) if File.basename(module_name) == "index"
    name = module_name == "." ? under : "#{under}/#{module_name}"
    preload = every_page.include?(name) || page_groups.fetch(name, "game")
    pin name, to: "#{under}/#{file}", preload: preload
  end
end
