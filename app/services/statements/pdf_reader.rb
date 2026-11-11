require "open3"

module Statements
  # Text PDFs -> one string per page (pdftotext -layout keeps the table columns aligned).
  # Scanned PDFs (little or no text) -> PNG page images for the vision model.
  class PdfReader
    MAX_PAGES = 40
    MIN_CHARS_PER_PAGE = 80 # below this, the page is treated as a scan
    RENDER_DPI = 150

    def initialize(path)
      @path = path
    end

    def page_count
      @page_count ||= begin
        out, _status = Open3.capture2("pdfinfo", @path.to_s)
        out[/^Pages:\s+(\d+)/, 1].to_i
      end
    end

    def text_pages
      @text_pages ||= begin
        out, err, status = Open3.capture3("pdftotext", "-layout", "-enc", "UTF-8", "-l", MAX_PAGES.to_s, @path.to_s, "-")
        raise ImportError, "PDF: #{err.presence || 'unreadable file'}" unless status.success?

        out.split("\f").map(&:rstrip).reject(&:blank?)
      end
    end

    def scanned?
      chars = text_pages.sum { |page| page.gsub(/\s/, "").length }
      chars < MIN_CHARS_PER_PAGE * [ page_count, 1 ].max
    end

    # Yields the PNG bytes of each page
    def each_page_image
      Dir.mktmpdir("statement-pages") do |dir|
        _out, err, status = Open3.capture3("pdftoppm", "-png", "-r", RENDER_DPI.to_s, "-l", MAX_PAGES.to_s,
                                           @path.to_s, File.join(dir, "page"))
        raise ImportError, "PDF: #{err.presence || 'cannot render pages'}" unless status.success?

        Dir.glob(File.join(dir, "page-*.png")).sort_by { |f| f[/(\d+)\.png\z/, 1].to_i }.each do |file|
          yield File.binread(file)
        end
      end
    end
  end
end
