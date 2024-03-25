require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::OllamaAgent do
  before(:each) do
    @valid_options = Agents::OllamaAgent.new.default_options
    @checker = Agents::OllamaAgent.new(:name => "OllamaAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
