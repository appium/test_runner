Test file with output.

```ruby
# encoding: utf-8
=begin
'--- before_first'

one | tests for test_runner | 1
'--- before'
'test one'

'--- after'

two | tests for test_runner | 2
'--- before'
'test two';
'--- after'
'--- after_last'

Finished in 0s
2 tests
=end
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
```
