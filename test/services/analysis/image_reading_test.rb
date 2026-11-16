require "test_helper"

module Analysis
  class ImageReadingTest < ActiveSupport::TestCase
    def op(date, amount) = { "date" => date, "amount" => amount, "description" => "x" }

    test "rows repeated where strips overlap are dropped" do
      top = [ op("22/05/2026", 260), op("23/05/2026", -1), op("23/05/2026", 13) ]
      bottom = [ op("23/05/2026", -1), op("2026-05-23", 13), op("24/05/2026", -40) ] # same rows, other date format
      merged = LLMExtractor.merge_strips([ top, bottom ])

      assert_equal [ 260, -1, 13, -40 ], merged.map { |o| o["amount"] }
    end

    test "identical operations inside one strip are kept" do
      merged = LLMExtractor.merge_strips([ [ op("23/05/2026", -5), op("23/05/2026", -5) ], [ op("24/05/2026", -7) ] ])
      assert_equal 3, merged.size
    end

    # Ollama aborts a looping reply with an error
    class LoopingLLM
      def self.chat(**) = raise(OllamaChat::Error, "Ollama API error: prediction aborted, token repeat limit reached")
    end

    test "a photo the model cannot read gives a clear message, not an Ollama error" do
      error = assert_raises(ImportError) { LLMExtractor.new(llm: LoopingLLM).from_images([ [ "png-bytes" ] ]) }
      assert_equal I18n.t("statements.errors.photo_unreadable"), error.message
    end

    test "phone photos are turned upright, shrunk and cut into overlapping strips" do
      skip "libvips is not installed (sudo apt install libvips42t64)" unless ImagePreparer.available?

      # A portrait page stored sideways with EXIF orientation 6, like a phone photo
      sideways = Vips::Image.black(4000, 3000).copy
      sideways.set_type(GObject::GINT_TYPE, "orientation", 6)
      strips = ImagePreparer.strips(sideways.write_to_buffer(".jpg"))
      first = Vips::Image.new_from_buffer(strips.first, "")

      assert_operator strips.size, :>, 1
      assert_equal ImagePreparer::MAX_WIDTH, first.width # upright: the short side is the width
      assert_equal 1, first.bands
    end

    test "thumbnails are refused as too small" do
      skip "libvips is not installed" unless ImagePreparer.available?

      tiny = Vips::Image.black(320, 240).write_to_buffer(".jpg")
      assert_raises(ImportError) { ImagePreparer.strips(tiny) }
    end
  end
end
