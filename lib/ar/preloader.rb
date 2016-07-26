require "ar/preloader/version"
require "rusql"

module Ar
  module Preloader
    class Error < RuntimeError
    end

    extend Rusql

    def self.preload_habtm(list:, name:, association_klass:, foreign_key:, association_foreign_key:, inner_associations:, join_table:, association_condition:)
      return if list.nil? || list.length == 0

      klass = list.first.class
      klass.send :attr_reader, name.to_sym

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

      associated_objects_hash = {}

      associated_objects_hash = associated_objects.map{ |e| [e[association_klass.primary_key.to_sym], e] }.to_h

      list.each do |ele|
        set = []

        join_objects.select{ |e| e[0] == ele[klass.primary_key.to_sym] }.map(&:last).each do |association_pk|
          if associated_objects_hash[association_pk].present?
            set << associated_objects_hash[association_pk]
          end
        end

        ele.instance_variable_set(:"@#{name}", set)
      end
    end

    def self.preload_has_many(list:, name:, association_klass:, foreign_key:, inner_associations: nil, association_condition: nil, reverse_association: nil)
      return if list.nil? || list.length == 0

      klass = list.first.class
      klass.send :attr_reader, name.to_sym

      if reverse_association.present?
        association_klass.send :attr_reader, reverse_association.to_sym
      end

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

      associated_objects_hash = {}
      associated_objects.each do |ao|
        associated_objects_hash[ao[foreign_key.to_sym]] ||= []
        associated_objects_hash[ao[foreign_key.to_sym]] << ao
      end

      list.each do |ele|
        set = []

        if associated_objects_hash[ele[klass.primary_key.to_sym]].present?
          set = associated_objects_hash[ele[klass.primary_key.to_sym]]
        end

        if reverse_association.present?
          set.each do |ao|
            ao.instance_variable_set(:"@#{reverse_association}", ele)
          end
        end

        ele.instance_variable_set(:"@#{name}", set)
      end
    end

    def self.preload_has_one(list:, name:, association_klass:, foreign_key:, order_type:, order_field:, inner_associations: nil, association_condition: nil, reverse_association: nil)
      return if list.nil? || list.length == 0

      klass = list.first.class
      klass.send :attr_reader, name.to_sym

      if reverse_association.present?
        association_klass.send :attr_reader, reverse_association.to_sym
      end

      query = <<-EOS.squish

      SELECT
        #{ association_klass.table_name }.*
      FROM #{ association_klass.table_name }
      INNER JOIN (
        SELECT #{ association_klass.table_name }.#{ foreign_key }, #{ order_type }(#{ association_klass.table_name }.#{ order_field }) max_#{ order_field }
        FROM #{ association_klass.table_name }
        WHERE #{ association_klass.table_name }.#{ foreign_key } IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })
          #{ association_condition.present? ? " AND #{ association_condition }" : "" }
        GROUP BY #{ association_klass.table_name }.#{ foreign_key }
      ) _association ON _association.#{ foreign_key } = #{ association_klass.table_name }.#{ foreign_key } AND _association.max_#{ order_field } = #{ association_klass.table_name }.#{ order_field }
      WHERE #{ association_klass.table_name }.#{ foreign_key } IN (#{ list.map{ |e| e[klass.primary_key.to_sym] }.compact.map(&:to_s).join(", ") })
        #{ association_condition.present? ? " AND #{ association_condition }" : "" }

      EOS

      associated_objects = association_klass.find_by_sql(query).to_a
      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = associated_objects.map{ |e| [e[foreign_key.to_sym], e] }.to_h

      list.each do |ele|
        if associated_objects_hash[ele[klass.primary_key.to_sym]].present?
          associated_object = associated_objects_hash[ele[klass.primary_key.to_sym]]
          if reverse_association.present?
            associated_object.instance_variable_set(:"@#{reverse_association}", ele)
          end
          ele.instance_variable_set(:"@#{name}", associated_object)
        end
      end
    end

    def self.preload_belongs_to(list:, name:, association_klass:, foreign_key:, inner_associations: nil, association_condition: nil, additional_selects: [], additional_joins: [])
      return if list.nil? || list.length == 0

      klass = list.first.class
      klass.send :attr_reader, name.to_sym

      return if list.map{ |e| e[foreign_key.to_sym] }.compact.length == 0

      association_table = table(association_klass.table_name.to_sym)

      selects = [association_table[:*]]
      selects += additional_selects

      condition = association_table[association_klass.primary_key.to_sym].in( list.map{ |e| e[foreign_key.to_sym] }.compact )

      unless association_condition.nil?
        condition = condition.and( association_condition )
      end

      query = select( *selects ).
        from( association_table ).
        where( condition )

      additional_joins.each do |j|
        query = query.join(j)
      end

      unless additional_selects.length == 0 && additional_joins.length == 0
        query = query.group_by( association_table[association_klass.primary_key.to_sym] )
      end

      associated_objects = association_klass.find_by_sql(query.to_s).to_a
      if inner_associations.present?
        associated_objects.prefetch(inner_associations)
      end

      associated_objects_hash = associated_objects.map{ |e| [e[association_klass.primary_key.to_sym], e] }.to_h

      list.each do |ele|
        if associated_objects_hash[ele[foreign_key.to_sym]].present?
          ele.instance_variable_set(:"@#{name}", associated_objects_hash[ele[foreign_key.to_sym]])
        end
      end
    end

    def self.preload_polymorphic_belongs_to(list:, name:, polymorphic_key_field:, polymorphic_type_field:, polymorphic_type_map:)
      return if list.nil? || list.length == 0

      return if polymorphic_key_field.nil? || polymorphic_type_field.nil? || polymorphic_type_map.nil? || (polymorphic_type_map.keys.length == 0)

      klass = list.first.class
      klass.send :attr_reader, name.to_sym

      polymorphic_type_map.keys.each do |polymorphic_type|
        matching_list = list.select{ |e| e[polymorphic_type_field.to_sym] == polymorphic_type }
        association_klass = polymorphic_type_map[polymorphic_type]
        Ar::Preloader.preload_belongs_to(
          list:              matching_list,
          name:              name,
          association_klass: association_klass,
          foreign_key:       polymorphic_key_field
        )
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
        && details[:type].present?

      case details[:type]
      when :belongs_to, "belongs_to"
        Ar::Preloader.preload_belongs_to(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          inner_associations:       details[:associations],
          additional_selects:       details[:additional_selects] || [],
          additional_joins:         details[:additional_joins] || [],
          association_condition:    details[:association_condition]
        )
      when :polymorphic_belongs_to, "polymorphic_belongs_to"
        Ar::Preloader.preload_polymorphic_belongs_to(
          list:                     self,
          name:                     name,
          polymorphic_key_field:    details[:polymorphic_key_field],
          polymorphic_type_field:   details[:polymorphic_type_field],
          polymorphic_type_map:     details[:polymorphic_type_map]
        )
      when :has_one, "has_one"
        Ar::Preloader.preload_has_one(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          order_type:               details[:order_type],
          order_field:              details[:order_field],
          inner_associations:       details[:associations],
          association_condition:    details[:association_condition],
          reverse_association:      details[:reverse_association]
        )
      when :has_many, "has_many"
        Ar::Preloader.preload_has_many(
          list:                     self,
          name:                     name,
          association_klass:        details[:klass],
          foreign_key:              details[:foreign_key],
          inner_associations:       details[:associations],
          association_condition:    details[:association_condition],
          reverse_association:      details[:reverse_association]
      )
      when :has_and_belongs_to_many, "has_and_belongs_to_many"
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
