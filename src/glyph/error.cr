# src/glyph/error.cr
class Glyph::Error < Exception
  enum Reason
    OutOfNamespace
    MalformedPayload
    PayloadTooLarge
    OutlineTooLarge

    def code : String
      case self
      in .out_of_namespace?  then "out_of_namespace"
      in .malformed_payload? then "malformed_payload"
      in .payload_too_large? then "payload_too_large"
      in .outline_too_large? then "outline_too_large"
      end
    end
  end

  getter reason : Reason

  def initialize(@reason : Reason)
    super(@reason.code)
  end
end
