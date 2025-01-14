require_relative 'control_domain'
require_relative 'control'
require_relative 'question'
require_relative 'answer_collection'
require_relative 'matrix_row'

require 'rubyXL'
require 'rubyXL/convenience_methods/cell'
require 'rubyXL/convenience_methods/workbook'
require 'rubyXL/convenience_methods/worksheet'

require 'elasticsearch'
require 'elastic-app-search'

module Csa::Ccm

class Matrix

  ATTRIBS = %i[
    version title source_file workbook source_path control_domains answers
  ].freeze

  attr_accessor *ATTRIBS

  def initialize(options = {})
    options.each_pair do |k, v|
      send("#{k}=", v)
    end

    @control_domains ||= {}
    @answers ||= AnswerCollection.new

    parse_version if @workbook 

    self
  end

  def source_file
    @source_file || File.basename(source_path)
  end

  def parse_version
    title_prefix = 'consensus assessments initiative questionnaire v'
    first_row = workbook[0][0]

    if first_row[4].value.downcase.start_with? title_prefix # version v3.1.0
      @version = first_row[4].value.downcase[title_prefix.length..-1]
    elsif first_row[2].value.downcase.start_with? title_prefix # version v3.0.1
      @version = first_row[2].value.downcase[title_prefix.length..-1]
    elsif first_row[0].value.downcase.start_with? title_prefix # version v1.1
      @version = first_row[0].value.downcase[title_prefix.length..-1]
    else # version 1.0
      @version = workbook[1][0][0].value[/(?<=Version )(\d+\.?)+(?= \()/]
    end
  end

  def worksheet
    workbook.worksheets.first
  end

  attr_reader :workbook

  def title
    worksheet[0][4].value # version v3.1.0
  end

  def metadata
    {
      'version' => version,
      # 'version' => '3.0.1',
      'title' => title,
      'source-file' => source_file
    }
  end

  def row(i)
    MatrixRow.new(worksheet[i])
  end

  def get_start_row(version)
    case version
    when '1.0'
      2
    when '1.1'
      3
    else
      # '3.0.1' and assume beyond
      4
    end
  end

  def answer_column_num(value)
    case value
    when 'yes', true
      5
    when 'no', false
      6
    when 'NA'
      7
    end
  end

  NOTES_COLUMN_NUM = 8 # Column 'I' in 3.0.1
  COLUMN_MARK_SYMBOL = 'x'
  INFOSEC_FUNCTION_COLUMN_NUM = 9
  INFOSEC_SERVICE_COLUMN_NUM = 10
  INFOSEC_LAST_REVIEW_DATE_COLUMN_NUM = 11

  def apply_answers(answers, skip_elastic_metadata)

    unless @version == answers.version
      raise "Matrix & AnswerCollection version mismatch (Matrix: #{matrix.version}, AnswerCollection: #{answers.version})"
    end

    # TODO: we should loop through all AnswerCollection, not all Questions
    all_rows = worksheet.sheet_data.rows

    start_row = get_start_row(@version)
    max_row_number = all_rows.length - 1
    

    (start_row..max_row_number).each do |row_number|
      question_id = worksheet[row_number][2].value
      # puts row_number
      answer = answers[question_id]

      next unless answer

      # puts '___________________________'
      # puts question_id
      # puts answer.inspect

      if answer.answer
        answer_col = answer_column_num(answer.answer)
        # puts "filling in answer #{worksheet[row_number][answer_col]} to #{answer.answer} as '#{COLUMN_MARK_SYMBOL}'"
        worksheet[row_number][answer_col].change_contents(COLUMN_MARK_SYMBOL)
      end

      if answer.comment
        # puts "filling in answer comment #{worksheet[row_number][NOTES_COLUMN_NUM]} to #{answer.comment}"
        worksheet[row_number][NOTES_COLUMN_NUM].change_contents(answer.comment)
      end

      # puts "Answer is now #{worksheet[row_number][answer_col].raw_value} and #{worksheet[row_number][NOTES_COLUMN_NUM].raw_value}"
      # puts '___________________________'

      #Applying Elastic InfoSec Metadata
      if skip_elastic_metadata == false
        worksheet[row_number][INFOSEC_FUNCTION_COLUMN_NUM].change_contents(answer.infosec_function)
        worksheet[row_number][INFOSEC_SERVICE_COLUMN_NUM].change_contents(answer.infosec_service)
        worksheet[row_number][INFOSEC_LAST_REVIEW_DATE_COLUMN_NUM].change_contents(answer.infosec_last_review_date)
      end
    end

    self
  end

  # Add single answer, fill in to XLSX
  # def add_answer(answer)
  # end

  def self.from_xlsx(input_file)
    matrix = Matrix.new(
      workbook: RubyXL::Parser.parse(input_file),
      source_path: input_file
    )

    all_rows = matrix.worksheet.sheet_data.rows

    start_row = matrix.get_start_row(matrix.version)
    max_row_number = all_rows.length - 1

    # We loop over all Questions
    (start_row..max_row_number).each do |row_number|
      # puts "looping row #{row_number}"
      row = matrix.row(row_number)
      # Skip row if there is no question-id
      # puts"row #{row.question_id}"
      # require 'pry'
      # binding.pry
      next if row.question_id.nil?

      domain_id = row.control_domain_id
      unless domain_id.nil?

        control_domain = matrix.control_domains[domain_id] ||
                         ControlDomain.new(
                           id: row.control_domain_id,
                           title: row.control_domain_title
                         )

        # Store the Control Domain
        matrix.control_domains[domain_id] = control_domain
      end

      control_id = row.control_id
      unless control_id.nil?

        control_domain = matrix.control_domains[domain_id]
        control = control_domain.controls[control_id] || Control.new(
          id: row.control_id,
          title: row.control_title,
          specification: row.control_spec
        )

        # Store the Control
        control_domain.controls[control_id] = control
      end

      # Store the Question
      control.questions[row.question_id] = Question.new(
        id: row.question_id,
        content: row.question_content
      )

      answer = if row.answer_na
                 'NA'
               elsif row.answer_no
                 'no'
               elsif row.answer_yes
                 'yes'
               end
      
      matrix.answers << Answer.new(
        question_id: row.question_id,
        control_id: control_id,
        answer: answer,
        comment: row.comment,
        infosec_function: row.infosec_function,
        infosec_service: row.infosec_service,
        infosec_last_review_date: (row.infosec_last_review_date).to_s
      )
    end

    matrix.answers.metadata = matrix.metadata

    matrix
  end

  def self.from_xlsx2es(input_file)
    matrix = Matrix.new(
      workbook: RubyXL::Parser.parse(input_file),
      source_path: input_file
    )
    
    client = Elasticsearch::Client.new(
      host: ENV['ZOCALO_URL'],
      api_key: {
        id: ENV['ZOCALO_API_ID'], 
        api_key: ENV['ZOCALO_API_KEY']
      },
      port: '443',
      scheme: 'https'
    )

    app_search_client = Elastic::AppSearch::Client.new(
      :api_key => ENV['ZOCALO_APP_SEARCH_PRIVATE_API'], 
      :api_endpoint => 'https://as-api.zocalo.inf.elasticnet.co/api/as/v1/'
    )

    all_rows = matrix.worksheet.sheet_data.rows

    start_row = matrix.get_start_row(matrix.version)
    max_row_number = all_rows.length - 1

    puts "Started Data Ingestion..."

    # We loop over all Questions
    (start_row..max_row_number).each do |row_number|
      # puts "looping row #{row_number}"
      row = matrix.row(row_number)
      # Skip row if there is no question-id
      # puts"row #{row.question_id}"
      # require 'pry'
      # binding.pry
      next if row.question_id.nil?
      
      domain_id = row.control_domain_id
      unless domain_id.nil?

        control_domain = matrix.control_domains[domain_id] ||
                         ControlDomain.new(
                           id: row.control_domain_id,
                           title: row.control_domain_title
                         )

        # Store the Control Domain
        matrix.control_domains[domain_id] = control_domain
      end

      control_id = row.control_id
      unless control_id.nil?

        control_domain = matrix.control_domains[domain_id]
        control = control_domain.controls[control_id] || Control.new(
          id: row.control_id,
          title: row.control_title,
          specification: row.control_spec
        )

        # Store the Control
        control_domain.controls[control_id] = control
      end

      # Store the Question
      control.questions[row.question_id] = Question.new(
        id: row.question_id,
        content: row.question_content
      )

      answer = if row.answer_na
                 'NA'
               elsif row.answer_no
                 'no'
               elsif row.answer_yes
                 'yes'
               end
      
      unless row.comment.nill?
        matrix.answers << Answer.new(
          question_id: row.question_id,
          control_id: control_id,
          answer: answer,
          comment: row.comment,
          infosec_function: row.infosec_function,
          infosec_service: row.infosec_service,
          infosec_last_review_date: (row.infosec_last_review_date).to_s
        )

        index = 'caiq-controls-answers'
        document_id = row.question_id
        body = {
          control_domain_id: row.control_domain_id,
          control_domain_title: control_domain.title,
          control_domain_control_id: row.control_id,
          control_domain_control_title: control.title,
          control_domain_control_specification: control.specification,
          control_domain_control_question_id: row.question_id,
          control_domain_control_question_content: row.question_content,
          question_answer: answer,
          question_comment: row.comment,
          infosec_function: row.infosec_function,
          infosec_service: row.infosec_service,
          infosec_last_review_date: (row.infosec_last_review_date).to_s
        }

        puts 'Ingesting ' + row.question_id + ' into Elasticsearch' 
        client.index(index: index, id: document_id, body: body)

        #AppSearch Ingestion

        engine_name = 'caiq-controls-answers'
        document = {
          :id => row.question_id,
          :control_domain_id => row.control_domain_id,
          :control_domain_title => control_domain.title,
          :control_domain_control_id => row.control_id,
          :control_domain_control_title => control.title,
          :control_domain_control_specification => control.specification,
          :control_domain_control_question_id => row.question_id,
          :control_domain_control_question_content => row.question_content,
          :question_answer => answer,
          :question_comment => row.comment,
          :infosec_function => row.infosec_function,
          :infosec_service => row.infosec_service,
          :infosec_last_review_date => (row.infosec_last_review_date).to_s
        }

        puts 'Ingesting ' + row.question_id + ' into AppSearch'
        app_search_client.index_document(engine_name, document)
      end
    end

    matrix
  end

  def to_control_hash
    {
      'ccm' => {
        'metadata' => metadata.to_hash,
        'control-domains' => control_domains.each_with_object([]) do |(_k, v), acc|
                               acc << v.to_hash
                             end
      }
    }
  end

  def to_control_file(filename)
    File.open(filename, 'w') do |file|
      file.write(to_control_hash.to_yaml)
    end
  end

  def to_xlsx(filename, skip_elastic_metadata)
    if skip_elastic_metadata == true
      worksheet.delete_column(11)
      worksheet.delete_column(10)
      worksheet.delete_column(9)
    end
    workbook.write(filename)
  end

end
end
