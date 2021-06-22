module Csa::Ccm

class Answer

  ATTRIBS = %i(
    control_id
    question_id
    answer
    comment
    infosec_function
    infosec_service
    infosec_last_review_date
  )

  attr_accessor *ATTRIBS

  def initialize(options={})
    options.each_pair do |k, v|
      send("#{k.to_s.tr('-', '_')}=", v)
    end

    self
  end

  def <=>(other)
    question_id <=> other.question_id
  end

  def to_hash(skip_elastic_metadata)
    # attribs = skip_comment ? ATTRIBS - [:comment] : ATTRIBS  #always want comment to be outputted
    # attribs = ATTRIBS
    if skip_elastic_metadata
      attribs = ATTRIBS - [:infosec_function] - [:infosec_service] - [:infosec_last_review_date]
    else
      attribs = ATTRIBS
    end

    attribs.inject({}) do |acc, attrib|
      value = send(attrib)
      if value.nil?
        acc
      else
        acc.merge(attrib.to_s.tr('_', '-') => value)
      end
    end
  end
end

end