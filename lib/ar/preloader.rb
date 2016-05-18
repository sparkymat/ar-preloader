require "ar/preloader/version"

module Ar
  module Preloader
    class Error < RuntimeError
    end

    def self.preload_habtm(list:, name:, association_klass:, foreign_key:, association_foreign_key:, inner_associations:, join_table:, association_condition:)
      klass = list.first.class
      klass.send :attr_reader, "_#{name}".to_sym

      join_query = <<-EOS

      SELECT
        #{join_table}.#{foreign_key},
        #{join_table}.#{association_foreign_key}
      FROM #{join_table}
      WHERE #{join_table}.#{foreign_key} IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })

      EOS

      join_objects = ActiveRecord::Base.connection.execute(join_query).to_a

      query = <<-EOS

      SELECT
        #{association_klass.table_name}.*
      FROM #{association_klass.table_name}
      INNER JOIN #{join_table} ON #{join_table}.#{association_foreign_key} = #{association_klass.table_name}.#{association_klass.primary_key}
      WHERE #{join_table}.#{foreign_key} IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })#{ association_condition.present? ? " AND #{association_condition}" : "" }

      EOS

      associated_objects = association_klass.find_by_sql(query).to_a

      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = associated_objects.map{ |e| [e[klass.primary_key.to_sym], e] }.to_h

      list.each do |ele|
        set = []

        join_objects.select{ |e| e[0] == ele[klass.primary_key.to_sym] }.map(&:last).each do |association_pk|
          if associated_objects_hash[association_pk].present?
            set << associated_objects_hash[association_pk]
          end
        end

        ele.instance_variable_set(:"@_#{name}", set)
      end
    end

    def self.preload_has_many(list:, name:, association_klass:, foreign_key:, inner_associations: nil, association_condition: nil)
      klass = list.first.class
      klass.send :attr_reader, "_#{name}".to_sym

      return if list.map{ |e| e[foreign_key.to_sym] }.compact.length == 0

      query = <<-EOS.squish

      SELECT
        #{association_klass.table_name}.*
      FROM #{association_klass.table_name}
      WHERE #{association_klass.table_name}.#{foreign_key} IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })#{ association_condition.present? ? "AND #{association_condition}" : ""}

      EOS

      associated_objects = klass.find_by_sql(query).to_a
      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = {}
      associated_objects.each do |ao|
        associated_objects_hash[ao[klass.primary_key.to_sym]] ||= []
        associated_objects_hash[ao[klass.primary_key.to_sym]] << ao
      end

      list.each do |ele|
        set = []

        if associated_objects_hash[ele[foreign_key.to_sym]].present?
          set = associated_objects_hash[ele[foreign_key.to_sym]]
        end

        ele.instance_variable_set(:"@_#{name}", set)
      end
    end

    def self.preload_has_one(list:, name:, association_klass:, foreign_key:, inner_associations: nil, association_condition: nil)
      klass = list.first.class
      klass.send :attr_reader, "_#{name}".to_sym

      query = <<-EOS.squish

      SELECT
        #{association_klass.table_name}.*
      FROM #{association_klass.table_name}
      WHERE #{association_klass.table_name}.#{foreign_key} IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })#{ association_condition.present? ? "AND #{association_condition}" : ""}

      EOS

      associated_objects = association_klass.find_by_sql(query).to_a
      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = associated_objects.map{ |e| [e[foreign_key.to_sym], e] }.to_h

      list.each do |ele|
        if associated_objects_hash[ele[klass.primary_key.to_sym]].present?
          ele.instance_variable_set(:"@_#{name}", associated_objects_hash[ele[klass.primary_key.to_sym]])
        end
      end
    end

    def self.preload_belongs_to(list:, name:, association_klass:, foreign_key:, inner_associations: nil, association_condition: nil)
      klass = list.first.class
      klass.send :attr_reader, "_#{name}".to_sym

      return if list.map{ |e| e[foreign_key.to_sym] }.compact.length == 0

      query = <<-EOS.squish

      SELECT
        #{association_klass.table_name}.*
      FROM #{association_klass.table_name}
      WHERE #{association_klass.table_name}.#{association_klass.primary_key} IN (#{ list.map{ |e| e[foreign_key.to_sym] }.compact.map(&:to_s).join(", ") })#{ association_condition.present? ? "AND #{association_condition}" : ""}

      EOS

      associated_objects = association_klass.find_by_sql(query).to_a
      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = associated_objects.map{ |e| [e[association_klass.primary_key.to_sym], e] }.to_h

      list.each do |ele|
        if associated_objects_hash[ele[foreign_key.to_sym]].present?
          ele.instance_variable_set(:"@_#{name}", associated_objects_hash[ele[foreign_key.to_sym]])
        end
      end
    end
  end
end

class Array
  def prefetch(args)
    return if args.keys.length == 0

    args.each_pair do |name, details|
      raise Ar::Preloader::Error.new("Incomplete relation details for '#{name}'") unless \
        details.is_a?(Hash) \
        && details[:klass].present?  \
        && details[:klass].ancestors.include?(ActiveRecord::Base)  \
        && details[:type].present? \
        && details[:foreign_key].present? 

      case details[:type].to_sym
      when :belongs_to
        Ar::Preloader.preload_belongs_to(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          inner_associations:       details[:associations],
          association_condition:    details[:association_condition]
        )
      when :has_one
        Ar::Preloader.preload_has_one(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          inner_associations:       details[:associations],
          association_condition:    details[:association_condition]
        )
      when :has_many,
        Ar::Preloader.preload_has_many(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          inner_associations:       details[:associations],
          association_condition:    details[:association_condition]
      )
      when :has_and_belongs_to_many
        Ar::Preloader.preload_habtm(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          association_foreign_key:  details[:association_foreign_key],
          inner_associations:       details[:associations],
          join_table:               details[:join_table],
          association_condition:    details[:association_condition]
        )
      end
    end
  end
end
