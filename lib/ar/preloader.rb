require "ar/preloader/version"

module Ar
  module Preloader
    class Error < RuntimeError
    end

    def self.check_association_exists(klass, association)
      case association
      when String, Symbol
        return klass.reflections.keys.include?(association.to_s)
      when Hash
        association.each_pair do |k,v|
          return false unless klass.reflections.keys.include?(k.to_s)

          associated_klass = klass.reflections[k.to_s].class_name.constantize

          case v
          when String, Symbol, Hash
            return false unless Ar::Preloader.check_association_exists(associated_klass, v)
          when Array
            v.each do |each_v|
              return false unless Ar::Preloader.check_association_exists(associated_klass, each_v)
            end
          else
          end
        end

        return true
      else
        return false
      end
    end

    def self.preload_association(list, association, inner_associations = [])
      return if list.length == 0

      case association
      when String, Symbol
        klass = list.first.class
        association_details = klass.reflections[association.to_s]
        association_klass = association_details.class_name.constantize

        case association_details
        when ActiveRecord::Reflection::HasManyReflection
          foreign_key = association_details.foreign_key
          association_pk = association_klass.primary_key

          query = <<-EOS
SELECT
  distinct #{association_klass.table_name}.*
FROM #{association_klass.table_name}
WHERE #{association_klass.table_name}.#{foreign_key} in (#{ list.map{ |e| e[klass.primary_key.to_sym].try(:to_s) }.compact.join(",") })

EOS

          association_list = association_klass.find_by_sql(query).to_a

          association_list.preload(*inner_associations)

          list.each do |obj|
            klass.send :attr_reader, "_#{association}".to_sym

            instance_variable_name = "@_#{association}".to_sym
            if obj.instance_variable_get(instance_variable_name).nil?
              obj.instance_variable_set(instance_variable_name, [])
            end

            association_list.select{ |e| e[foreign_key.to_sym] == obj[klass.primary_key.to_sym] }.each do |association_obj|
              each_list = obj.instance_variable_get(instance_variable_name)
              each_list << association_obj
              obj.instance_variable_set(instance_variable_name, each_list)
            end
          end
        when ActiveRecord::Reflection::BelongsToReflection
          foreign_key = association_details.foreign_key
          association_pk = association_klass.primary_key

          query = <<-EOS
SELECT
  distinct #{association_klass.table_name}.*
FROM #{association_klass.table_name}
WHERE #{association_klass.table_name}.#{association_klass.primary_key} in (#{ list.map{ |e| e[foreign_key.to_sym].try(:to_s) }.compact.join(",") })

EOS

          association_list = association_klass.find_by_sql(query).to_a

          association_list.preload(*inner_associations)

          association_map = association_list.map{ |e| [e[e.class.primary_key.to_sym], e] }.to_h

          list.each do |obj|
            if obj[foreign_key.to_sym].present? && association_map[obj[foreign_key.to_sym]].present?
              klass.send :attr_reader, "_#{association}".to_sym
              obj.instance_variable_set( "@_#{association}".to_sym, association_map[obj[foreign_key.to_sym]] )
            end
          end
        else
          raise Ar::Preloader::Error.new("Unsupported assocation type: '#{assocation}'")
        end
      when Hash
        association.each_pair do |k,v|
          Ar::Preloader.preload_association(list, k, [v])
        end
      end
    end
  end
end

class Array
  def preload(*args)
    return if args.length == 0

    raise Ar::Preloader::Error.new("Cannot preload. Mixed type lists are not supported.") if (self.map(&:class).uniq.count > 1)
    raise Ar::Preloader::Error.new("Cannot preload. At least one element in array is not an ActiveRecord object.") if (self.reject{|e| e.is_a?(ActiveRecord::Base) }.count > 0)

    args.each do |arg|
      raise Ar::Preloader::Error.new("Cannot find association '#{arg}' on one or more of the ActiveRecord objects.") if (self.reject{|e| Ar::Preloader.check_association_exists(e.class, arg) }.count > 0)
    end

    args.each do |arg|
     Ar::Preloader.preload_association(self, arg) 
    end

    true
  end
end
