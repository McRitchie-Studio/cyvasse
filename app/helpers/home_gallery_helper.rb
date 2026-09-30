module HomeGalleryHelper
  # A srcset with width descriptors from HomeGallery::Slide#wide_images or
  # #portrait_images: "/assets/…/dragon-<digest>.webp 1800w, …-2x-<digest>.webp 3600w".
  # The <picture> and the page's preload both use it, so the browser picks
  # the same file for each and never fetches a slide twice.
  def home_gallery_srcset(images)
    images.map { |path, width| "#{image_path(path)} #{width}w" }.join(", ")
  end
end
