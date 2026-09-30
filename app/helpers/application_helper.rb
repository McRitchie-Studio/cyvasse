module ApplicationHelper
  # A page asks for the JavaScript it mounts, by its page group in
  # config/importmap.rb ("game", "seek", "home"): one modulepreload per module
  # pinned to that group. Pins preloaded on every page (preload: true) are the
  # engine head's already, so they are left out here.
  #
  # The tags go in content_for(:module_preloads), which the layout yields AFTER
  # the engine head and so after the import map. Not :head: that yields before
  # the import map, and a module fetch started before the import map is parsed
  # makes the browser ignore the map.
  def preload_modules(group)
    content_for(:module_preloads, module_preload_tags(group))
  end

  def module_preload_tags(group)
    packages = Rails.application.importmap.preloaded_module_packages(
      resolver: self, entry_point: group, cache_key: "page-group-#{group}"
    )
    paths = packages.filter_map { |path, package| path unless package.preload == true }
    javascript_module_preload_tag(*paths)
  end
end
