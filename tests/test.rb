require 'rubygems'
require 'test_runner'

describe 'tests for test_runner' do
  after do; '--- after' end
  before do; '--- before' end
  after_last do; '--- after_last' end
  before_first do; '--- before_first' end
  t 'one' do
    'test one'
  end
  t 'two' do; 'test two'; end
end

describe 'describe 2' do
  t 'three' do
    '3'
  end
end
