module Analysis
  # Prepares a photo or scanned page for the vision model (gemma4 sees every image at a small fixed size):
  #   1. rotates it upright from its EXIF orientation: phone photos are stored sideways with a rotation flag,
  #      which Ollama ignores, so the model saw the statement on its side and read nothing or looped;
  #   2. grayscale, at most MAX_WIDTH wide;
  #   3. cuts it into overlapping horizontal strips, so the text of each strip stays readable.
  # Needs libvips (ruby-vips): `sudo apt install libvips42t64`, already in the Dockerfile.
  module ImagePreparer
    module_function

    MIN_SIDE = 600       # smaller images (thumbnails, messenger previews) can't be read
    MAX_WIDTH = 1800
    STRIP_HEIGHT = 900
    OVERLAP = 0.18       # a little more than one statement row, so a row cut at an edge is whole in the next strip

    def available?
      require "vips"
      Vips::Image.respond_to?(:new_from_buffer)
    rescue LoadError, NameError
      false
    end

    # => array of PNG strips, top to bottom
    def strips(bytes)
      image = upright(bytes)
      return [ png(image) ] if image.height <= STRIP_HEIGHT * 1.3

      overlap = (STRIP_HEIGHT * OVERLAP).round
      count = ((image.height - overlap).to_f / (STRIP_HEIGHT - overlap)).ceil
      step = (image.height - STRIP_HEIGHT).to_f / (count - 1)
      Array.new(count) { |i| png(image.crop(0, (i * step).round, image.width, STRIP_HEIGHT)) }
    end

    # Two overlapping halves of a strip (when the model got stuck on the whole strip)
    def halves(png_bytes)
      image = Vips::Image.new_from_buffer(png_bytes, "")
      height = (image.height * (0.5 + OVERLAP / 2)).round
      [ png(image.crop(0, 0, image.width, height)), png(image.crop(0, image.height - height, image.width, height)) ]
    end

    def upright(bytes)
      raise ImportError, I18n.t("statements.errors.image_support_missing") unless available?

      image = Vips::Image.new_from_buffer(bytes, "").autorot
      if [ image.width, image.height ].min < MIN_SIDE
        raise ImportError, I18n.t("statements.errors.image_too_small", width: image.width, height: image.height)
      end

      image = image.colourspace(:b_w) if image.bands >= 3
      image = image.extract_band(0) if image.bands > 1 # drop alpha
      image.width > MAX_WIDTH ? image.resize(MAX_WIDTH.to_f / image.width) : image
    end

    def png(image)
      image.write_to_buffer(".png")
    end
  end
end
