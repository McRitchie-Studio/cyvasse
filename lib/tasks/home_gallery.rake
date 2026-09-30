namespace :cyvasse do
  # Re-captures the front door's background gallery (HomeGallery) from staged
  # board states on /play: test/capture/home_gallery_capture.rb. PIECES=a,b
  # limits it to those pieces; PREVIEW=1 also saves each whole board to
  # tmp/home_gallery. Needs Chrome and cwebp.
  desc "Capture the home page's per-piece background shots"
  task :capture_home_gallery do
    sh({ "RAILS_ENV" => "test" }, "bin/rails", "test", "test/capture/home_gallery_capture.rb")
  end

  # Re-captures the /rules banner (a Heavy Horse with the enemy King in reach)
  # from the same script's RULES scene. PREVIEW=1 saves its whole board too.
  desc "Capture the rules page's banner"
  task :capture_rules_hero do
    sh({ "RAILS_ENV" => "test", "RULES" => "1" }, "bin/rails", "test", "test/capture/home_gallery_capture.rb")
  end
end
