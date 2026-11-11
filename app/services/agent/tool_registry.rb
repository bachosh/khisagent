# app/services/agent/tool_registry.rb
module Agent
  # Global tool catalogue (Ruby's version of the Python @register_tool decorator)
  class ToolRegistry
    class << self
      def tools
        @tools ||= {}
      end

      def tools_by_tag
        @tools_by_tag ||= Hash.new { |h, k| h[k] = [] }
      end

      def register(name, function, description: nil, parameters: nil, terminal: false, tags: [])
        metadata = build_metadata(
          name: name,
          function: function,
          description: description,
          parameters: parameters,
          terminal: terminal,
          tags: tags
        )

        tools[name] = metadata

        # Index by tags
        tags.each do |tag|
          tools_by_tag[tag] << name unless tools_by_tag[tag].include?(name)
        end

        metadata
      end

      def get_by_tags(tags)
        tool_names = tags.flat_map { |tag| tools_by_tag[tag] }.uniq
        tool_names.map { |name| tools[name] }.compact
      end

      def get(name)
        tools[name]
      end

      def clear
        tools.clear
        tools_by_tag.clear
      end

      private

      def build_metadata(name:, function:, description:, parameters:, terminal:, tags:)
        {
          name: name,
          function: function,
          description: description || "No description provided",
          parameters: parameters || auto_generate_parameters(function),
          terminal: terminal,
          tags: tags
        }
      end

      # Builds a JSON schema from the lambda's keyword arguments (all typed as strings).
      # Prefer writing the schema by hand: types and descriptions help the LLM.
      def auto_generate_parameters(function)
        schema = { type: "object", properties: {}, required: [] }

        function.parameters.each do |type, name|
          next if [ :block, :rest, :keyrest ].include?(type)

          schema[:properties][name] = { type: "string" }
          schema[:required] << name if [ :req, :keyreq ].include?(type)
        end

        schema
      end
    end
  end
end
