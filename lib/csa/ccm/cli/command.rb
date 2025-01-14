require 'rake'
require 'thor'

require_relative 'ui'
require_relative '../cli'
require_relative '../matrix'
require_relative '../answer_collection'

module Csa
  module Ccm
    module Cli
      class Command < Thor
        desc 'ccm-yaml VERSION', 'Generating a machine-readable CCM/CAIQ'
        option :output_file, aliases: :o, type: :string, desc: 'Optional output YAML file. If missed, the input file’s name will be used'

        def ccm_yaml(caiq_version)
          input_files = Resource.lookup_version(caiq_version)

          unless input_files && !input_files.empty?
            UI.say("No file found for #{caiq_version} version")
            return
          end

          input_file = input_files.first

          unless File.exist? input_file
            UI.say("#{input_file} doesn't exists for #{caiq_version} version")
            return
          end

          matrix = Matrix.from_xlsx(input_file)

          output_file = options[:output_file] || "caiq-#{matrix.version}.yaml"
          matrix.to_control_file(output_file)
        end

        desc "xlsx2yaml XLSX_PATH", "Converting CCM XSLX to YAML"
        option :output_file, aliases: :o, type: :string, desc: "Optional output YAML file. If missed, the input file’s name will be used"

        def xlsx2yaml(input_xlsx_file)
          unless input_xlsx_file
            UI.say("#{input_xlsx_file} file doesn't exists")
            return
          end

          matrix = Matrix.from_xlsx(input_xlsx_file)

          output_file = options[:output_file] || input_xlsx_file.gsub('.xlsx', '.yaml')
          matrix.to_control_file(output_file)
        end

        desc "caiq2yaml XLSX_PATH", "Converting a filled CAIQ to YAML"
        option :output_name, aliases: :n, type: :string, desc: "Optional output CAIQ YAML file. If missed, the input file’s name will be used"
        option :output_path, aliases: :p, type: :string, desc: "Optional output directory for result file. If missed, pwd will be used"
        option :comment, aliases: :s, type: :boolean, desc: "[true|false] Optional skip comments in result file. if missed, comments are retained"

        def caiq2yaml(input_xlsx_file)
          unless input_xlsx_file
            UI.say("#{input_xlsx_file} file doesn't exists")
            return
          end

          matrix = Matrix.from_xlsx(input_xlsx_file)

          base_output_file = options[:output_name] ||
            File.basename(input_xlsx_file.gsub('.xlsx', ''))

          if options[:output_path]
            base_output_file = File.join(options[:output_path], base_output_file)
          end

          control_output_file = "#{base_output_file}.control.yaml"
          answers_output_file = "#{base_output_file}.answers.yaml"

          matrix.to_control_file(control_output_file)
          matrix.answers.to_file(answers_output_file, options[:skip_comment])
        end

        desc "generate-with-answers ANSWERS_YAML", "Writing to the CAIQ XSLX template using YAML"
        option :template_path, aliases: :t, type: :string, desc: "Optional input template CAIQ XSLT file. If missed -r will be checked"
        option :caiq_version, aliases: :r, type: :string, default: "3.1", desc: "Optional input template CAIQ XSLT version. If missed -t will be checked"
        option :output_file, aliases: :o, type: :string, desc: 'Optional output XSLT file. If missed, the input file’s name will be used' 
        option :skip_elastic_metadata, aliases: :s, type: :boolean, default: true, desc: 'Optional to decide whether to include Elastic InfoSec Metadata within the XLSX or not. If missed, InfoSec Metadata will not be included in the final XLSX.'  

        def generate_with_answers(answers_yaml_path)
          unless File.exist? answers_yaml_path
            UI.say("#{answers_yaml_path} file doesn't exists")
            puts "#{answers_yaml_path} file doesn't exists"
            return
          end

          unless options[:template_path] || options[:caiq_version]
            UI.say("No input template specified by -r or -t")
            # puts "No input template specified by -r or -t"
            return
          end

          template_xlsx_path = options[:template_path]
          unless template_xlsx_path
            caiq_version = options[:caiq_version]
            input_files = Resource.lookup_version(caiq_version)

            unless input_files && !input_files.empty?
              UI.say("No file found for #{caiq_version} version")
              # puts "No file found for #{caiq_version} version"
              return
            end

            input_files.sort! do |a, b|
              date_str_a = a.match(/\d\d-\d\d-\d\d\d\d/)[0].to_s
              date_str_b = b.match(/\d\d-\d\d-\d\d\d\d/)[0].to_s

              date_a = DateTime.parse date_str_a, 'dd-mm-YYYY'
              date_b = DateTime.parse date_str_b, 'dd-mm-YYYY'

              date_b <=> date_a
            end

            puts 'XLSX resources templates being used:'
            puts input_files
            template_xlsx_path = input_files.first
          end

          unless File.exist? template_xlsx_path
            UI.say("#{template_xlsx_path} file doesn't exists")
            return
          end

          output_file = options[:output_file]
          unless options[:output_file]
            output_file = answers_yaml_path.gsub('.yaml', '.xlsx')
          end

          answers = AnswerCollection.from_yaml(answers_yaml_path)
          # puts answers.values
          matrix = Matrix.from_xlsx(template_xlsx_path)
          # puts matrix

          matrix.apply_answers(answers, options[:skip_elastic_metadata])
          matrix.to_xlsx(output_file, options[:skip_elastic_metadata])

          puts 'XLSX to YAML conversation complete!'
        end

        desc "caiq2es XLSX_PATH", "Converting a filled CAIQ to YAML and ingesting into ES"
        option :output_name, aliases: :n, type: :string, desc: "Optional output CAIQ YAML file. If missed, the input file’s name will be used"
        option :output_path, aliases: :p, type: :string, desc: "Optional output directory for result file. If missed, pwd will be used"
        option :comment, aliases: :s, type: :boolean, desc: "[true|false] Optional skip comments in result file. if missed, comments are retained"

        def caiq2es(input_xlsx_file)
          unless input_xlsx_file
            UI.say("#{input_xlsx_file} file doesn't exists")
            return
          end

          Matrix.from_xlsx2es(input_xlsx_file)

          puts "All data ingested!"
        end
      end
    end
  end
end
