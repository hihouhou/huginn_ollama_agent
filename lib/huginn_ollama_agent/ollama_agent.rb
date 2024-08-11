module Agents
  class OllamaAgent < Agent
    include FormConfigurable
    can_dry_run!
    no_bulk_receive!
    default_schedule 'every_1h'

    description do
      <<-MD
      The Ollama Agent interacts with Ollama's api.

      The `type` can be like generate.

      `debug` is used for verbose mode.

      `model` (required) the model name.

      `prompt` the prompt to generate a response.

      `image` is a base64-encoded image or URL (for multimodal models such as llava).

      `context` the context parameter returned from a previous request to /generate, this can be used to keep a short conversational memory.

      `stream` if false the response will be returned as a single response object, rather than a stream of objects.

      `raw` if true no formatting will be applied to the prompt. You may choose to use the raw parameter if you are specifying a full templated prompt in your request to the API.

      `expected_receive_period_in_days` is used to determine if the Agent is working. Set it to the maximum number of days
      that you anticipate passing without this Agent receiving an incoming Event.
      MD
    end

    event_description <<-MD
      Events look like this:

         {
            "model": "mistral",
            "created_at": "2024-03-25T20:54:25.920292408Z",
            "response": " I'm assuming you're asking if the question or instruction provided in the prompt is clear and effective. To answer that, I would need to see the specific prompt you have in mind. If you could please share it with me, I'd be happy to help evaluate its clarity and effectiveness.",
            "done": true,
            "context": [
              733,
              16289,
              28793,
              28705,
              1235,
              272,
              11510,
              771,
              1550,
              733,
              28748,
              16289,
              28793,
              315,
              28742,
              28719,
              16347,
              368,
              28742,
              267,
              7201,
              513,
              272,
              2996,
              442,
              13126,
              3857,
              297,
              272,
              11510,
              349,
              3081,
              304,
              5645,
              28723,
              1791,
              4372,
              369,
              28725,
              315,
              682,
              927,
              298,
              1032,
              272,
              2948,
              11510,
              368,
              506,
              297,
              2273,
              28723,
              1047,
              368,
              829,
              4665,
              4098,
              378,
              395,
              528,
              28725,
              315,
              28742,
              28715,
              347,
              4610,
              298,
              1316,
              15627,
              871,
              25312,
              304,
              23798,
              28723
            ],
            "total_duration": 12033891123,
            "load_duration": 921427821,
            "prompt_eval_count": 14,
            "prompt_eval_duration": 1246297000,
            "eval_count": 62,
            "eval_duration": 9865732000
          }

    MD

    def default_options
      {
        'type' => 'generate',
        'model' => 'mistral',
        'url' => '',
        'prompt' => '',
        'context' => '',
        'stream' => 'false',
        'raw' => 'false',
        'debug' => 'false',
        'expected_receive_period_in_days' => '2',
      }
    end

    form_configurable :type, type: :array, values: ['generate']
    form_configurable :model, type: :string
    form_configurable :url, type: :string
    form_configurable :prompt, type: :string
    form_configurable :image, type: :string
    form_configurable :context, type: :string
    form_configurable :stream, type: :boolean
    form_configurable :raw, type: :boolean
    form_configurable :debug, type: :boolean
    form_configurable :expected_receive_period_in_days, type: :string
    def validate_options
      errors.add(:base, "type has invalid value: should be 'generate'") if interpolated['type'].present? && !%w(generate).include?(interpolated['type'])

      unless options['model'].present?
        errors.add(:base, "model is a required field")
      end

      unless options['url'].present?
        errors.add(:base, "url is a required field")
      end

      unless options['prompt'].present?
        errors.add(:base, "prompt is a required field")
      end

      if options.has_key?('stream') && boolify(options['stream']).nil?
        errors.add(:base, "if provided, stream must be true or false")
      end

      if options.has_key?('raw') && boolify(options['raw']).nil?
        errors.add(:base, "if provided, raw must be true or false")
      end

      if options.has_key?('debug') && boolify(options['debug']).nil?
        errors.add(:base, "if provided, debug must be true or false")
      end

      unless options['expected_receive_period_in_days'].present? && options['expected_receive_period_in_days'].to_i > 0
        errors.add(:base, "Please provide 'expected_receive_period_in_days' to indicate how many days can pass before this Agent is considered to be not working")
      end
    end

    def working?
      event_created_within?(options['expected_receive_period_in_days']) && !recent_error_logs?
    end

    def receive(incoming_events)
      incoming_events.each do |event|
        interpolate_with(event) do
          log event
          trigger_action
        end
      end
    end

    def check
      trigger_action
    end

    private


    def log_curl_output(code,body)

      log "request status : #{code}"

      if interpolated['debug'] == 'true'
        log "request status : #{code}"
        log "body"
        log body
      end

    end

    def push_model(model)

      uri = URI.parse(interpolated['url'] + '/api/pull')
      request = Net::HTTP::Post.new(uri)
      request.body = JSON.dump({
        "name" => interpolated['model']
      })

      req_options = {
        use_ssl: uri.scheme == "https",
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

    end

    def check_remote_model()
      url = URI(interpolated['url'] + '/api/tags')
      https = Net::HTTP.new(url.host, url.port)

      request = Net::HTTP::Get.new(url)
      response = https.request(request)

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      payload['models'].each do |modele|
        return true if modele['name'] == interpolated['model'] + ':latest'
      end

      false
    end

    def encode_to_base64(data)
      return Base64.strict_encode64(data)
    end

    def download_and_convert_to_base64(url)
      begin
        uri = URI(url)
        response = Net::HTTP.get_response(uri)

        log_curl_output(response.code,response.body)

        if response.is_a?(Net::HTTPSuccess)
          file_data = response.body
          base64_data = encode_to_base64(file_data)
          return base64_data
        end
      end
    end

    def detect_image_source(input)
      if input =~ URI::DEFAULT_PARSER.regexp[:ABS_URI]
        download_and_convert_to_base64(interpolated['image'])
      elsif input.match?(/\A(?:[A-Za-z0-9+\/]{4})*(?:[A-Za-z0-9+\/]{2}==|[A-Za-z0-9+\/]{3}=)?\z/)
        begin
          decoded = Base64.strict_decode64(input)
          if Base64.strict_encode64(decoded) == input
            return input
          end
        end
      end
    end

    def generate_completion()

      request_payload = {}
      request_payload['model'] = interpolated['model']
      request_payload['prompt'] = interpolated['prompt']
      request_payload['stream'] = boolify(interpolated['stream'])
      request_payload['raw'] = boolify(interpolated['raw'])
      request_payload['context'] = interpolated['context'].split(',').map(&:strip).map(&:to_i) if !interpolated['context'].empty?
      request_payload['images'] = ["#{detect_image_source(interpolated['image'])}"] if !interpolated['image'].empty?

      if check_remote_model()
        if interpolated['debug'] == 'true'
          log "#{interpolated['model']} found"
        end
      else
        if interpolated['debug'] == 'true'
          log "#{interpolated['model']} not found"
        end
        push_model(interpolated['model'])
      end

      uri = URI.parse(interpolated['url'] + '/api/generate')
      request = Net::HTTP::Post.new(uri)
      request.body = JSON.dump(request_payload)

      req_options = {
        use_ssl: uri.scheme == "https",
        read_timeout: 120
      }

      response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
        http.request(request)
      end

      log_curl_output(response.code,response.body)

      payload = JSON.parse(response.body)
      create_event payload: payload

    end
    

    def trigger_action

      case interpolated['type']
      when "generate"
        generate_completion()
      else
        log "Error: type has an invalid value (#{type})"
      end
    end
  end
end
