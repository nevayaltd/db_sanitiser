module DbSanitiser
  class Runner
    def initialize(file_name)
      @file_name = file_name
    end

    def sanitise
      run(Strategies::SanitiseStrategy.new)
    end

    def validate
      run(Strategies::ValidateStrategy.new)
    end

    private

    def run(strategy)
      config = File.read(@file_name)
      dsl = RootDsl.new(strategy)
      dsl.instance_eval(config)
      strategy.after_run(dsl.instance_variable_get('@table_names').to_a)
    end
  end

  module Strategies
    class SanitiseStrategy
      def sanitise_table(table_name, columns_to_sanitise, where_query, ignored_columns)
        update_values = columns_to_sanitise.to_a.map do |(key, value)|
          "`#{key}` = #{value}"
        end
        scope = active_record_class(table_name)
        scope = scope.where(where_query) if where_query
        scope.update_all(update_values.join(', '))
      end

      def delete_all(table_name)
        active_record_class(table_name).delete_all
      end

      def after_run(processed_tables)
      end

      private

      def active_record_class(table_name)
        Class.new(ActiveRecord::Base) { self.table_name = table_name }
      end
    end

    class ValidateStrategy
      ACTIVERECORD_META_TABLES = %w(schema_migrations ar_internal_metadata)

      def sanitise_table(table_name, columns_to_sanitise, where_query, ignored_columns)
        ar_class = active_record_class(table_name)
        columns = columns_to_sanitise.keys + ignored_columns

        validate_columns_are_accounted_for(ar_class, table_name, columns)
      end

      def delete_all(table_name)
      end

      def after_run(processed_tables)
        tables_in_db = ActiveRecord::Base.connection.tables
        tables_not_accounted_for = tables_in_db - ACTIVERECORD_META_TABLES - processed_tables
        unless tables_not_accounted_for.empty?
          fail "Missing tables: #{tables_not_accounted_for.inspect}"
        end
      end

      private

      def active_record_class(table_name)
        Class.new(ActiveRecord::Base) { self.table_name = table_name }
      end

      def validate_columns_are_accounted_for(active_record_class, table_name, columns)
        columns_not_accounted_for = active_record_class.column_names - columns
        unless columns_not_accounted_for.empty?
          fail "Missing columns for #{table_name}: #{columns_not_accounted_for.inspect}"
        end

        unknown_columns = columns - active_record_class.column_names
        unless unknown_columns.empty?
          fail "Unknown columns for #{table_name}: #{unknown_columns.inspect}"
        end
      end
    end
  end

  class RootDsl
    def initialize(strategy)
      @strategy = strategy
      @table_names = Set.new
    end

    def sanitise_table(table_name, &block)
      @table_names.add(table_name)
      dsl = SanitiseDsl.new(table_name, &block)
      dsl._run(@strategy)
    end

    def delete_all(table_name)
      @table_names.add(table_name)
      dsl = DeleteAllDsl.new(table_name)
      dsl._run(@strategy)
    end
  end

  class SanitiseDsl
    def initialize(table_name, &block)
      @table_name = table_name
      @block = block
      @columns_to_sanitise = {}
      @columns_to_ignore = []
    end

    def _run(strategy)
      instance_eval(&@block)

      strategy.sanitise_table(@table_name, @columns_to_sanitise, @where_query, @columns_to_ignore)
    end

    def string(value)
      "\"#{value}\""
    end

    def sanitise(name, sanitised_value)
      @columns_to_sanitise[name] = sanitised_value
    end

    def where(query)
      @where_query = query
    end

    def ignore(*columns)
      @columns_to_ignore += columns
    end
  end

  class DeleteAllDsl
    def initialize(table_name)
      @table_name = table_name
    end

    def _run(strategy)
      strategy.delete_all(@table_name)
    end
  end
end
