# frozen_string_literal: true

module Decidim
  module CensusConnector
    module Seeds
      def seed_scopes(organization, options = {})
        Scopes.new.seed organization, options
      end

      class Scopes
        def seed(organization, options = {})
          @organization = organization

          path = File.join(options[:base_path], "scopes")

          puts "Loading scope types..."
          @scope_types = Hash.new { |h, k| h[k] = Hash.new { |h2, k2| h2[k2] = {} } }
          CSV.foreach(File.join(path, "scope_types.tsv"), col_sep: "\t", headers: true) do |row|
            @scope_types[row["Code"]][:id] = row["UID"]
            @scope_types[row["Code"]][:organization] = @organization
            @scope_types[row["Code"]][:name][row["Locale"]] = row["Singular"]
            @scope_types[row["Code"]][:plural][row["Locale"]] = row["Plural"]
          end

          Decidim::ScopeType.transaction do
            @scope_types.values.each do |info|
              Decidim::ScopeType.find_or_initialize_by(id: info[:id]).update!(info)
            end
            max_id = Decidim::ScopeType.maximum(:id)
            Decidim::ScopeType.connection.execute("ALTER SEQUENCE decidim_scope_types_id_seq RESTART WITH #{max_id + 1}")
          end

          puts "Loading scopes..."
          @translations = Hash.new { |h, k| h[k] = {} }
          CSV.foreach(File.join(path, "scopes.translations.tsv"), col_sep: "\t", headers: true) do |row|
            @translations[row["UID"]][row["Locale"]] = row["Translation"]
          end

          @scope_ids = {}
          CSV.foreach(File.join(path, "scopes.tsv"), col_sep: "\t", headers: true) do |row|
            save_scope row
          end
          print "\r"
        end

        private

        def root_code(code)
          code.split(/\W/i).first
        end

        def parent_code(code)
          return nil if code == Decidim::CensusConnector.census_local_code
          parent_code = code.rindex(/\W/i)
          parent_code ? code[0..parent_code - 1] : EXTERIOR_SCOPE
        end

        def save_scope(row)
          print "\r#{row["UID"].ljust(30)}"
          code = row["UID"]

          scope = Decidim::Scope.create!(
            code: code,
            organization: @organization,
            scope_type_id: @scope_types[row["Type"]][:id],
            name: @translations[code],
            parent_id: @scope_ids[parent_code(code)]
          )
          @scope_ids[code] = scope.id
        end
      end
    end
  end
end