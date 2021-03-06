module B :
sig
  type st = St
  type bs = Bs

  module Bigstring :
  sig
    open Bigarray

    type t = (char, int8_unsigned_elt, c_layout) Array1.t

    val length    : t -> int
    val create    : int -> t
    val get       : t -> int -> char
    val set       : t -> int -> char -> unit
    val sub       : t -> int -> int -> t
    val fill      : t -> char -> unit
    val copy      : t -> t
    val get_u16   : t -> int -> int
    val get_u32   : t -> int -> int32
    val get_u64   : t -> int -> int64
    val set_u16   : t -> int -> int -> unit
    val set_u32   : t -> int -> int32 -> unit
    val set_u64   : t -> int -> int64 -> unit
    val to_string : t -> string
    val blit      : t -> int -> t -> int -> int -> unit
    val pp        : Format.formatter -> t -> unit
    val empty     : t
  end

  type 'a t =
    | Bytes     : Bytes.t -> st t
    | Bigstring : Bigstring.t -> bs t

  val from_bytes      : Bytes.t -> st t
  val from_bigstring  : Bigstring.t -> bs t
  val from            : proof: 'a t -> int -> 'a t

  val length          : 'a t -> int
  val get             : 'a t -> int -> char
  val set             : 'a t -> int -> char -> unit

  val get_u16         : 'a t -> int -> int
  val get_u32         : 'a t -> int -> int32
  val get_u64         : 'a t -> int -> int64
  val set_u16         : 'a t -> int -> int -> unit
  val set_u32         : 'a t -> int -> int32 -> unit
  val set_u64         : 'a t -> int -> int64 -> unit

  val to_string       : 'a t -> string

  val blit            : 'a t -> int -> 'a t -> int -> int -> unit
  val sub             : 'a t -> int -> int -> 'a t
  val fill            : 'a t -> int -> int -> char -> unit
  val pp              : Format.formatter -> 'a t -> unit
  val empty           : proof:'a t -> 'a t

  val proof_bytes     : st t
  val proof_bigstring : bs t
end

(** Decompress, functionnal implementation of Zlib in OCaml. *)

(** Hunk definition.

    [Match (len, dist)] means a repeating previous pattern of [len + 3] bytes
    at [dist + 1] before the current cursor.
    [Literal chr] means a character.
*)
module Hunk :
sig
  type t =
    | Match of (int * int) (** [Match (len, dist)] where [len] and [dist] are
                               biased. The really [len] is [len + 3] and the
                               really [dist] is [dist + 1].

                               A [Match] means a repeating previous pattern of
                               [len + 3] byte(s) at [dist + 1] before the
                               current cursor.
                            *)
    | Literal of char (** [Literal chr] means a character. *)
end

(** Lz77 algorithm.

    A functionnal non-blocking implementation of Lz77 algorithm. This algorithm
    produces a [Hunk.t list] of an input.
*)
module L :
sig
  (** Lz77 error. *)
  type error =
    | Invalid_level of int (** This error appears when you try to
                               compute the Lz77 algorithm with a
                               wrong level
                               ([level >= 0 && level <= 9]).
                            *)
    | Invalid_wbits of int (** This error appears when you specify a bad wbits:
                               [wbits >= 8 && wbits <= 15]
                            *)

  (** The state of the Lz77 algorithm. *)
  type 'i t

  (** Pretty-printer of Lz77 error. *)
  val pp_error : Format.formatter -> error -> unit

  (** Pretty-printer of Lz77 state. *)
  val pp       : Format.formatter -> 'i t -> unit

  (** [used_in t] returns [n] bytes(s) used by the algorithm in the current
      input. *)
  val used_in  : 'i t -> int

  (** [default ~level ~on wbits] produces a new state to compute the Lz77
      algorithm in an input. [level] means the level of the compression
      (between 0 and 9), [on] is a function called when the algorithm produce
      one [Hunk.t] and [wbits] is the window size allowed.

      Usually, [wbits = 15] for a window of 32K. If [wbits] is lower, you
      constraint the distance of a [Match] produced by the Lz77 algorithm to
      the window size.
  *)
  val default  : ?level:int -> ?on:(Hunk.t -> unit) -> int -> 'i t
end

(** Deflate algorithm.

    A functionnal non-blocking implementation of Zlib algorithm.
*)
module type DEFLATE =
sig
  (** Deflate error. *)
  type error =
    | Lz77_error of L.error (** This error appears when the Lz77
                                algorithm produces an error, see
                                {!L.error}.
                             *)

  (** Frequencies module.

      This is the representation of the frequencies used by the deflate
      algorithm.
  *)
  module F : sig type t = int array * int array end

  (** The state of the deflate algorithm. ['i] and ['o] are the implementation
      used respectively for the input and the ouput, see {!B.st} and {!B.bs}.
      The typer considers than ['i = 'o].
  *)
  type ('i, 'o) t

  (** Pretty-printer of deflate error. *)
  val pp_error        : Format.formatter -> error -> unit

  (** Pretty-printer of deflate state. *)
  val pp              : Format.formatter -> ('i, 'o) t -> unit

  (** [get_frequencies t] returns the current frequencies of the deflate state.
      See {!F.t}.
   *)
  val get_frequencies : ('i, 'o) t -> F.t

  (** [set_frequencies f t] replaces the frequencies of the state [t] by [f].
      The paranoid mode (if [paranoid = true]) checks if the frequencies
      can be used with the internal [Hunk.t list]. That means, for all
      characters and patterns (see {!Hunk.t}), the binding
      frequencie must be [> 0].

      eg. if we have a [Literal 'a'], [(fst f).(Char.code 'a') > 0].
   *)
  val set_frequencies : ?paranoid:bool -> F.t -> ('i, 'o) t -> ('i, 'o) t

  (** [finish t] means all input was sended. [t] will produce a new zlib block
      with the [final] flag and write the checksum of the input stream.
   *)
  val finish          : ('i, 'o) t -> ('i, 'o) t

  (** [no_flush off len t] means to continue the compression of an input at
      [off] on [len] byte(s).
   *)
  val no_flush        : int -> int -> ('i, 'o) t -> ('i, 'o) t
  val partial_flush   : int -> int -> ('i, 'o) t -> ('i, 'o) t
  val sync_flush      : int -> int -> ('i, 'o) t -> ('i, 'o) t
  val full_flush      : int -> int -> ('i, 'o) t -> ('i, 'o) t

  type meth = PARTIAL | SYNC | FULL

  (** [flush_of_meth meth] returns the function depending to the method. Like,
      [flush_of_meth SYNC] returns [sync_flush]. It's a convenience function,
      nothing else.
  *)
  val flush_of_meth   : meth -> (int -> int -> ('i, 'o) t -> ('i, 'o) t)

  (** [flush off len t] allows the state [t] to use an output at [off] on [len]
      byte(s).
   *)
  val flush           : int -> int -> ('i, 'o) t -> ('i, 'o) t

  (** [eval i o t] computes the state [t] with the input [i] and the ouput [o].
      This function returns:
      - [`Await t]: the state [t] waits a new input
      - [`Flush t]: the state [t] completes the output, may be you use
        {!flush}.
      - [`End t]: means that the deflate algorithm is done in your input. May
        be [t] writes something in your output. You can check with {!used_out}.
      - [`Error (t, exn)]: the algorithm catches an error [exn].
   *)
  val eval            : 'a B.t -> 'a B.t -> ('a, 'a) t ->
    [ `Await of ('a, 'a) t
    | `Flush of ('a, 'a) t
    | `End   of ('a, 'a) t
    | `Error of ('a, 'a) t * error ]

  (** [used_in t] returns how many byte(s) was used by [t] in the input. *)
  val used_in         : ('i, 'o) t -> int

  (** [used_out t] returns how many byte(s) was used by [t] in the output. *)
  val used_out        : ('i, 'o) t -> int

  (** [default ~proof ?wbits level] makes a new state [t]. [~proof] is an
      ['a B.t] specialized with an implementation (see {!B.st} or {!B.bs}) to
      informs the state wich implementation you use.

      [?wbits] (by default, [wbits = 15]) it's the size of the window used by
      the Lz77 algorithm (see {!L.default}).

      [?meth] can be specified to flush the internal buffer of the compression
      and create a new zlib block at [n] bytes specified.

      [level] is level compression:
      - 0: a stored compression (no compression)
      - 1 .. 3: a fixed compression (compression with a static huffman tree)
      - 4 .. 9: a dynamic compression (compression with a canonic huffman tree
                produced by the input)
   *)
  val default         : proof:'o B.t -> ?wbits:int -> int -> ('i, 'o) t

  (** [to_result i o refill flush t] is a convenience function to apply the
      deflate algorithm on the stream [refill] and call [flush] when the
      internal output is full (and need to flush).

      If the compute catch an error, we returns [Error exn]
      (see {!DEFLATE.error}). Otherwise, we returns the state {i useless} [t].
   *)
  val to_result : 'a B.t -> 'a B.t -> ?meth:(meth * int) ->
                  ('a B.t -> int option -> int) ->
                  ('a B.t -> int -> int) ->
                  ('a, 'a) t -> (('a, 'a) t, error) result

  (** Specialization of {!to_result} with {!B.Bytes.t}. *)
  val bytes     : Bytes.t -> Bytes.t -> ?meth:(meth * int) ->
                  (Bytes.t -> int option -> int) ->
                  (Bytes.t -> int -> int) ->
                  (B.st, B.st) t -> ((B.st, B.st) t, error) result

  (** Specialization of {!to_result} with {!B.Bigstring.t}. *)
  val bigstring : B.Bigstring.t -> B.Bigstring.t -> ?meth:(meth * int) ->
                  (B.Bigstring.t -> int option -> int) ->
                  (B.Bigstring.t -> int -> int) ->
                  (B.bs, B.bs) t -> ((B.bs, B.bs) t, error) result
end

module Deflate : DEFLATE

(** Window used by the Inflate algorithm.

    A functionnal implementation of window to use with the inflate algorithm.
    After one process, you can [reset] and reuse the window for a new process.
    This API is available to limit the allocation by Decompress.
*)
module Window :
sig
  type 'o t

  val create : proof:'o B.t -> 'o t
  val reset  : 'o t -> 'o t
  val crc    : 'o t -> Int32.t
end

(** Inflate algorithm.

    A functionnal non-blocking implementation of Zlib algorithm.
*)
module type INFLATE =
sig
  (** Inflate error. *)
  type error =
    | Invalid_kind_of_block (** This error appears when the kind of
                                the current block is wrong.
                             *)
    | Invalid_complement_of_length (** This error appears when we
                                       compute a stored block and
                                       length do not correspond with
                                       the complement of length.
                                    *)
    | Invalid_dictionary (** This error appears when we compute a
                             dynamic block and we catch an error when
                             we try to decode the dictionary.
                           *)
    | Invalid_crc (** The checksum of the output produced does not
                                   equal with the checksum of the stream.
                                 *)

  (** The state of the inflate algorithm. ['i] and ['o] are the implementation
      used respectively for the input and the output, see {!B.st} and {!B.bs}.
      The typer considers than ['i = 'o].
  *)
  type ('i, 'o) t

  (** Pretty-printer of inflate error. *)
  val pp_error : Format.formatter -> error -> unit

  (** Pretty-printer of inflate state. *)
  val pp       : Format.formatter -> ('i, 'o) t -> unit

  (** [eval i o t] computes the state [t] with the input [i] and the output
      [o]. This function returns:
      - [`Await t]: the state [t] waits a new input, may be you use {!refill}.
      - [`Flush t]: the state [t] completes the output, may be you use
        {!flush}.
      - [`End t]: means that the deflate algorithm is done in your input. May
        be [t] writes something in your output. You can check with {!used_out}.
      - [`Error (t, exn)]: the algorithm catches an error [exn].
    *)
  val eval     : 'a B.t -> 'a B.t -> ('a, 'a) t ->
    [ `Await of ('a, 'a) t
    | `Flush of ('a, 'a) t
    | `End   of ('a, 'a) t
    | `Error of ('a, 'a) t * error ]

  (** [refill off len t] allows the state [t] to use an output at [off] on
      [len] byte(s).
    *)
  val refill   : int -> int -> ('i, 'o) t -> ('i, 'o) t

  (** [flush off len t] allows the state [t] to use an output at [off] on [len]
      byte(s).
    *)
  val flush    : int -> int -> ('i, 'o) t -> ('i, 'o) t

  (** [used_in t] returns how many byte(s) was used by [t] in the input. *)
  val used_in  : ('i, 'o) t -> int

  (** [used_out ŧ] returns how many byte(s) was used by [t] in the output. *)
  val used_out : ('i, 'o) t -> int

  (** [write t] returns the size of the stream decompressed. *)
  val write    : ('i, 'o) t -> int

  (** [default] makes a new state [t]. *)
  val default  : 'o Window.t -> ('i, 'o) t

  (** [to_result i o refill flush t] is a convenience function to apply the
      inflate algorithm on the stream [refill] and call [flush] when the
      internal output is full (and need to flush).

      If the compute catch an error, we returns [Error exn]
      (see {!INFLATE.error}). Otherwise, we returns the state {i useless} [t].
  *)
  val to_result : 'a B.t -> 'a B.t ->
                  ('a B.t -> int) ->
                  ('a B.t -> int -> int) ->
                  ('a, 'a) t -> (('a, 'a) t, error) result

  (** Specialization of {!to_result} with {!B.Bytes.t}. *)
  val bytes     : Bytes.t -> Bytes.t ->
                  (Bytes.t -> int) ->
                  (Bytes.t -> int -> int) ->
                  (B.st, B.st) t -> ((B.st, B.st) t, error) result

  (** Specialization of {!to_result} with {!B.Bigstring.t}. *)
  val bigstring : B.Bigstring.t -> B.Bigstring.t ->
                  (B.Bigstring.t -> int) ->
                  (B.Bigstring.t -> int -> int) ->
                  (B.bs, B.bs) t -> ((B.bs, B.bs) t, error) result
end

module Inflate : INFLATE
