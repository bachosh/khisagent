module IconHelper
  ICON_DIR = Rails.root.join("app", "assets", "svgs")

  # Inline SVG from app/assets/svgs (Heroicons outline). Unknown names fall back to "photo".
  def svg_icon(name, options = {})
    svg = icon_source(name.to_s).dup
    attrs = +""
    attrs << %( class="#{ERB::Util.html_escape(options[:class])}") if options[:class]
    attrs << %( style="#{ERB::Util.html_escape(options[:style])}") if options[:style]
    svg.sub("<svg", "<svg#{attrs}").html_safe
  end

  private

  def icon_source(name)
    cache = (IconHelper.instance_variable_get(:@cache) || IconHelper.instance_variable_set(:@cache, {}))
    cache.delete_if { true } if Rails.env.development? && cache.size > 200
    cache[name] ||= begin
      path = ICON_DIR.join("#{name}.svg")
      path = ICON_DIR.join("photo.svg") unless name.match?(/\A[a-z0-9-]+\z/) && path.file?
      File.read(path).strip
    end
  end
end
