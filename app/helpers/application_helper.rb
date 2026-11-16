module ApplicationHelper
  MARKDOWN = Redcarpet::Markdown.new(
    Redcarpet::Render::HTML.new(filter_html: true, no_images: true, no_styles: true, safe_links_only: true,
                                hard_wrap: true, link_attributes: { target: "_blank", rel: "noopener" }),
    tables: true, autolink: true, strikethrough: true, no_intra_emphasis: true, fenced_code_blocks: true
  )

  # Model output → HTML. Redcarpet escapes raw HTML (filter_html), then sanitize as a second guard.
  def markdown(text)
    sanitize(MARKDOWN.render(text.to_s), tags: %w[ p br strong em del ul ol li h1 h2 h3 h4 a code pre blockquote table thead tbody tr th td hr ],
                                           attributes: %w[ href target rel ])
  end

  def money(amount, currency = nil, precision: 2)
    return "—" if amount.nil?

    number = number_with_delimiter(number_with_precision(amount, precision: precision), delimiter: " ")
    currency ? "#{number} #{currency}" : number
  end

  def signed_money(amount, currency = nil)
    prefix = amount.to_f.positive? ? "+" : ""
    "#{prefix}#{money(amount, currency)}"
  end

  def percent(value)
    value.nil? ? "—" : "#{number_with_precision(value, precision: 1, strip_insignificant_zeros: true)}%"
  end

  def nav_link(label, path, icon:, active: current_page?(path), css: "header__nav-link")
    link_to path, class: [ css, ("is-active" if active) ], aria: { current: (active ? "page" : nil) } do
      safe_join([ svg_icon(icon), tag.span(label) ])
    end
  end

  def page_classes
    [ content_for(:body_class), ("has-right-nav" if content_for?(:right_nav)) ].compact.join(" ")
  end

  def short_date(date)
    date ? l(date.to_date, format: :short_date) : "—"
  end
end
