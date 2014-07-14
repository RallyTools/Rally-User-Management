# Helper Class to help Logger output to both STOUT and to a file
# Attribution: see http://goo.gl/m7CUIC

module RallyUserManagement

    class MultiIO
      def initialize(*targets)
         @targets = targets
      end

      def write(*args)
        @targets.each {|t| t.write(*args)}
      end

      def close
        @targets.each(&:close)
      end
    end
end