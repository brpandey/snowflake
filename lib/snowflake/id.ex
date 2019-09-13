defmodule Snowflake.Id do
  @moduledoc """
  Module contains an implementation of a guaranteed globally unique id methodology.

  The unix Epoch timestamp is with milliseconds precision using 42 bits giving us 2^42.
  Or alternatively the max value being
  > :math.pow(2,42)
  4398046511104.0 (subtracting 1)

  > 4398046511103 |> DateTime.from_unix!(:millisecond)
  ~U[2109-05-15 07:35:11.103Z]
  So we have about 90 years left or about ~139 years for custom epoch

  Node ID using 10 bits gives us 2^10 or 1024 nodes.
  Machine local counter using 12 bits gives us 2^12 or up to 4095
  Since we really need only 2^9 or 128 values since we are assuming 100 requests per millisecond max
  the extra bits can serve as padding if we need to scale more beyond 100 req/ms or 100,000 req/s

  Given that the time clocks are mostly accurate per node we use timestamps as the basis for our unique id.
  We then append the node id to prevent timestamp collisions across different nodes
  We later append the counter id to prevent against id collisions that are generated
  at the submillisecond level on the same node
  If the state timestamp (which is recorded after every unique id generation) is the same as the most recent timestamp
  we only increment and append the counter with a new value otherwise if the timestamps are different there is no risk
  of collision so we just append the counter value of 0

  NOTE: I did have the originaly strategy of instead of appending a counter value
  appending some random bits say between 0 and factor k * 1024 where k is an integer >= 1.
  The problem was it wasn't straightforward to ensure the random numbers
  retrieved back were uniformly distributed enough even though I now erlang has :random.uniform it is still a PRNG.
  While low, the chance for collisions could present itself.
  Using monotonicly increasing atomic counters has eliminated the need to gamble with random number collision
  probabilities since it is deterministic as long as we are increment the counter and timestamp state on each
  successive unique id generation request.

  Lastly, it may prove fruitful to shorten the sequence bits from 12 to say 9 and add a few bits
  for a data center id in case our notion of node includes more than 1 data center.

  From a time standpoint I understand there can ntp time drift between data centers vs on a LAN
  There are some high precision clocks -- using gps and pps type clocks which allow for more precision -- that would
  potentially negate the need for this but I'm guessing these aren't as commonly used.
  """

  @total_bits 64
  @time_bits 42
  @node_bits 10
  @ctr_bits 12

  # 2^10 is 1024, we can support values 0 to 1023
  @max_node_id (:math.pow(2, @node_bits) - 1) |> Kernel.trunc()

  # 2*12 is 4096, we can support values 0 to 4096, even though we need only up to about 128
  # since the assumption is 100,000 requests per second or 100 requests per millisecond
  @max_ctr_id (:math.pow(2, @ctr_bits) - 1) |> Kernel.trunc()

  @doc """
  Please implement the following function.
  64 bit non negative integer output
  """

  # if timestamps are same, then increment counter
  def get_id(tstamp, {tstamp, node_id, counter_ref, counter})
      when node_id >= 0 and node_id <= @max_node_id and
             counter >= 0 and counter <= @max_ctr_id do
    # tstamp = timestamp()
    :ok = :counters.add(counter_ref, 1, 1)
    counter = :counters.get(counter_ref, 1)
    unique_id = encode_u64_id(tstamp, node_id, counter)
    {unique_id, {tstamp, node_id, counter_ref, counter}}
  end

  # if timestamps are different, reset counter to 0 since timestamp base has changed
  def get_id(tstamp2, {tstamp, node_id, counter_ref, counter})
      when tstamp2 != tstamp and node_id <= @max_node_id and node_id >= 0 and counter >= 0 and
             counter <= @max_ctr_id do
    :counters.put(counter_ref, 1, 0)
    counter = :counters.get(counter_ref, 1)
    unique_id = encode_u64_id(tstamp2, node_id, counter)
    {unique_id, {tstamp2, node_id, counter_ref, counter}}
  end

  def get_id(_t1, {_t2, node_id, _counter_ref, counter}) do
    raise "Surpassed node id (#{inspect(node_id)}) and counter value (#{inspect(counter)}) limits"
  end

  @doc """
  Returns timestamp since the epoch start in milliseconds.
  """
  @spec timestamp() :: non_neg_integer
  def timestamp do
    :os.system_time(:millisecond)
  end

  @spec encode_u64_id(integer, integer, integer) :: non_neg_integer
  def encode_u64_id(timestamp, node_id, counter) do
    # Construct the bytes that sum upto 64 bits
    bytes = <<timestamp::size(@time_bits), node_id::size(@node_bits), counter::size(@ctr_bits)>>

    # assert size is 64, byte size can be determined in constant time
    @total_bits = Kernel.byte_size(bytes) * 8

    # Decode into an unsigned integer
    _unique_id = bytes |> :binary.decode_unsigned()
  end

  @spec decode_u64_id(non_neg_integer) :: {integer, integer, integer}
  def decode_u64_id(unique_id) do
    bytes = unique_id |> :binary.encode_unsigned()

    @total_bits = Kernel.byte_size(bytes) * 8

    <<tstamp::size(@time_bits), node_id::size(@node_bits), counter::size(@ctr_bits)>> = bytes
    {tstamp, node_id, counter}
  end
end
