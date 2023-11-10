A Ruby library that facilitates thread-safe batch processing of 
messages. In certain situations, processing multiple messages in batch 
is more efficient than handling them one by one.

Consider a scenario where code receives events at random intervals and 
must notify an external HTTP service about these events. The straightforward 
approach is to issue an HTTP request with the details of each event as it is received. However, if events occur frequently, this method can lead to significant time spent on network latency. A more efficient approach is to aggregate events and send them in a single batched HTTP request.

This library is designed to handle exactly that. Events are pushed into 
the class instance, and a callback with batched data is triggered under 
one of two conditions:

* The number of messages in the batch reaches the specified maximum.
* The batch is not yet complete, but the maximum idle time has elapsed.

The latter condition is crucial for scenarios like the following: 
suppose you've set up a *batcher* to fire after receiving 10 messages, 
but only 9 messages are received, and no new messages are forthcoming. 
In this case, the callback with 9 messages will fire after the 
maximum idle time has passed.

## Usage
The following code creates a *batcher* with a maximum capacity of 10 
messages per batch and a maximum idle time of 3 seconds. The callback 
block simply prints the timestamp, batch size, and content.
```
require 'msg-batcher'

batcher = MsgBatcher.new 10, 3000 do |batch|
  now = Time.now
  timestamp = "#{now.min}:#{now.sec}"
  puts "[#{timestamp}] size: #{batch.size} content: #{batch.inspect}"
end

29.times do |i|
  batcher.push i
end

sleep 5
batcher.kill
```
The output is:
```
[10:12] size: 10 content: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
[10:12] size: 10 content: [10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
[10:15] size: 9 content: [20, 21, 22, 23, 24, 25, 26, 27, 28]
```
As you can see, the first two batches, each of size 10, were created immediately, while the last incomplete batch 
took 3 seconds to be created.

Finally, it's a good idea to call the `#kill` method when you no longer need the *batcher*. 
This method terminates the timer thread that was created during the 
*batcher*'s initialization.

## Thread-safety
The `#push` method is thread-safe. 

## Installation
### Bundler
Add this line to your application's Gemfile:
```
gem 'msg-batcher'
```
And then execute:
```
$ bundle install
```
### Standalone
Or install it yourself as:
```
gem install msg-batcher
```

