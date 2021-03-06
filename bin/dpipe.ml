let () = Printexc.record_backtrace true

module B = Decompress.B

external bs_read : Unix.file_descr -> B.Bigstring.t -> int -> int -> int =
  "bigstring_read" [@@noalloc]
external bs_write : Unix.file_descr -> B.Bigstring.t -> int -> int -> int =
  "bigstring_write" [@@noalloc]

(** Abstract [Unix.read] with ['a B.t]. *)
let unix_read (type a) ch (tmp : a B.t) off len = match tmp with
  | B.Bytes v -> Unix.read ch v off len
  | B.Bigstring v -> bs_read ch v off len

let unix_write (type a) ch (tmp : a B.t) off len = match tmp with
  | B.Bytes v -> Unix.write ch v off len
  | B.Bigstring v -> bs_write ch v off len

let _chunk = 0xFFFF

let do_command mode level wbits =
  let src = B.from ~proof:B.proof_bigstring _chunk in
  let dst = B.from ~proof:B.proof_bigstring _chunk in

  match mode with
  | `Compression ->
    let t = Decompress.Deflate.default ~proof:src ~wbits level in
    let r = Decompress.Deflate.to_result
      src dst
      (fun src -> function
       | Some max -> unix_read Unix.stdin src 0 (min max _chunk)
       | None -> unix_read Unix.stdin src 0 _chunk)
      (fun dst len -> let _ = unix_write Unix.stdout dst 0 len in _chunk)
      t
    in (match r with
        | Ok _ -> ()
        | Error exn -> Format.eprintf "%a\n%!" Decompress.Deflate.pp_error exn)
  | `Decompression ->
    let w = Decompress.Window.create ~proof:dst in
    let t = Decompress.Inflate.default w in
    let r = Decompress.Inflate.to_result
      src dst
      (fun src -> unix_read Unix.stdin src 0 _chunk)
      (fun dst len ->
       let _ = unix_write Unix.stdout dst 0 len in _chunk)
      t
    in (match r with
        | Ok _ -> ()
        | Error exn -> Format.eprintf "%a\n%!" Decompress.Inflate.pp_error exn)

open Cmdliner

let nat a b =
  let parse s =
    try let v = int_of_string s in
        let p = Printf.sprintf in
        match v, a, b with
        | v, Some a, Some b when a <= v && v <= b -> `Ok v
        | v, Some a, None when a <= v -> `Ok v
        | v, None, Some b when v <= b -> `Ok v
        | v, None, None -> `Ok v
        | _, Some a, Some b ->
          failwith (p "%s must be >= %d and <= %d" s a b)
        | _, Some a, None ->
          failwith (p "%s must be >= %d" s a)
        | _, None, Some b ->
          failwith (p "%s must be <= %d" s b)
    with Failure e -> `Error e
  in parse, Format.pp_print_int

let mode =
  let parse = function
    | "compression" -> `Ok `Compression
    | "decompression" -> `Ok `Decompression
    | _ -> `Error "Invalid mode"
  in
  parse, (fun fmt -> function
          | `Compression -> Format.pp_print_string fmt "compression"
          | `Decompression -> Format.pp_print_string fmt "decompression")

let mode =
  let doc = "Compression or decompression" in
  Arg.(value & opt mode `Compression & info ["mode"] ~doc)

let wbits =
  let doc = "Size of window (window bits between 8 and 15)" in
  Arg.(value & opt (nat (Some 8) (Some 15)) 15 & info ["wbits"] ~doc)

let level =
  let doc = "Level of compression" in
  Arg.(value & opt (nat (Some 0) (Some 9)) 4 & info ["level"] ~doc)

let command =
  let doc = "Deflate and inflate any document." in
  let man =
  [ `S "Description"
  ; `P "$(tname) takes a standard input and write in standard output the \
        compressed/uncompressed data." ]
  in
  Term.(pure do_command $ mode $ level $ wbits),
  Term.info "dpipe" ~doc ~man

let () = match Term.eval command with
  | `Error _ -> exit 1
  | _ -> exit 0
