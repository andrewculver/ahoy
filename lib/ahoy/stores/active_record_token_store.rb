module Ahoy
  module Stores
    class ActiveRecordTokenStore < BaseStore
      def track_visit(options, &block)
      end

      def track_event(name, properties, options, &block)
        if self.class.uses_deprecated_subscribers?
          options[:controller] ||= controller
          options[:user] ||= user
          options[:visit] ||= visit
          options[:visit_token] ||= ahoy.visit_token
          options[:visitor_token] ||= ahoy.visitor_token

          subscribers = Ahoy.subscribers
          if subscribers.any?
            subscribers.each do |subscriber|
              subscriber.track(name, properties, options.dup)
            end
          else
            $stderr.puts "No subscribers"
          end
        else
          event =
            site.events.new do |e|
              e.visit_id = visit(options).try(:id)
              e.user = user if e.respond_to?(:user=)
              e.name = name
              e.properties = properties
              e.time = options[:time]
              e.visitor = visitor
              # if an email was specified, make sure we record that.
              if properties['email'].present? && e.visitor.email != properties['email']
                e.visitor.email = properties['email']
              end
              e.visitor.last_event_at = Time.zone.now
              e.visitor.save

            end

          yield(event) if block_given?

          event.save!

          visit = event.visit
          unless visit.site
            visit.site = event.site
            visit.save
          end
        end
      end

      def site
        @site ||= Site.find_by(uuid: ahoy.request.params['events'].first['properties']['site'])
      end

      def visitor
        @visitor ||= site.visitors.find_or_create_by(uuid: ahoy.visitor_token)
      end

      def visit(options = {})
        @visit ||= (site.visits.where(visit_token: ahoy.visit_token).first if ahoy.visit_token)

        unless @visit

          @visit =
            site.visits.new do |v|
              v.visitor = visitor
              v.visit_token = ahoy.visit_token
              v.visitor_token = ahoy.visitor_token
              v.user = user if v.respond_to?(:user=)
              v.started_at = options[:started_at] if v.respond_to?(:started_at)
              v.created_at = options[:started_at] if v.respond_to?(:created_at)
            end

          set_visit_properties(@visit)

          yield(@visit) if block_given?

          begin
            @visit.save!
            geocode(@visit)
          rescue *unique_exception_classes
            # reset to nil so subsequent calls to track_event will load visit from DB
            @visit = nil
          end

        end

        @visit

      end

      def exclude?
        (!Ahoy.track_bots && bot?) ||
          (
            if Ahoy.exclude_method
              warn "[DEPRECATION] Ahoy.exclude_method is deprecated - use exclude? instead"
              if Ahoy.exclude_method.arity == 1
                Ahoy.exclude_method.call(controller)
              else
                Ahoy.exclude_method.call(controller, request)
              end
            else
              false
            end
          )
      end

      def user
        nil
      end

      class << self
        def uses_deprecated_subscribers
          warn "[DEPRECATION] Ahoy subscribers are deprecated"
          @uses_deprecated_subscribers = true
        end

        def uses_deprecated_subscribers?
          @uses_deprecated_subscribers || false
        end
      end

      protected

      def event_model
        site.events
      end
    end
  end
end
