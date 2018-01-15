module DbSanitiser
  class Runner
    def initialize(file_name)
      @file_name = file_name
    end

    def sanitise
      config = File.read(@file_name)
      dsl = RootDsl.new
      dsl.instance_eval(config)
    end
  end

  class RootDsl
    def sanitise_table(table_name, &block)
      dsl = SanitiseDsl.new(table_name, &block)
      dsl._run
    end

    def delete_all(table_name)
      dsl = DeleteAllDsl.new(table_name)
      dsl._run
    end
  end

  class SanitiseDsl
    def initialize(table_name, &block)
      @table_name = table_name
      @block = block
      @columns_to_sanitise = {}
      @columns_to_ignore = []
    end

    def _run
      instance_eval(&@block)

      validate_columns_are_accounted_for(@columns_to_sanitise.keys + @columns_to_ignore)
      update_values = @columns_to_sanitise.to_a.map do |(key, value)|
        "`#{key}` = #{value}"
      end
      scope = active_record_class
      scope = scope.where(@where_query) if @where_query
      scope.update_all(update_values.join(', '))
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

    private

    def active_record_class
      table_name = @table_name
      @ar_class ||= Class.new(ActiveRecord::Base) { self.table_name = table_name }
    end

    def validate_columns_are_accounted_for(columns)
      columns_not_accounted_for = active_record_class.column_names - columns
      unless columns_not_accounted_for.empty?
        fail "Missing columns for #{@table_name}: #{columns_not_accounted_for.inspect}"
      end
    end
  end

  class DeleteAllDsl
    def initialize(table_name)
      @table_name = table_name
    end

    def _run
      active_record_class.delete_all
    end

    private

    def active_record_class
      table_name = @table_name
      @ar_class ||= Class.new(ActiveRecord::Base) { self.table_name = table_name }
    end
  end
end
