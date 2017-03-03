Decompress - Pure OCaml implementation of Zlib
=============================================

[![Build Status](https://travis-ci.org/oklm-wsh/Decompress.svg)](https://travis-ci.org/oklm-wsh/Decompress)

Decompress  is  a  pur implementation  of  `zlib`.  The  goal  is  to  create an
available package for Mirage OS for `zlib` in OCaml (instead a C code).

We  respect   the  interface  of  `zlib`   and  all  flush   mode  is  available
(experimental):
- `SYNC_FLUSH`
- `PARTIAL_FLUSH`
- `FULL_FLUSH`

The interface proposed is a non-blocking interface.

Home page: http://din.osau.re/

Contact: Romain Calascibetta `<romain.calascibet ta@gmail.com>`

## Installation

Decompress can be installed with `opam`:

    opam install decompress

## Sample programs

Sample program are  located in the `bin` directory  of the distribution.  It can
be built  with (dependancy  with Unix  module,  the `cmdliner`  package and  a C
code):

    ocamlbuild -use-ocamlfind bin/dpipe.native

Another good example is provided in `bin/easy.ml` with the signature:

```ocaml
val compress : ?level:int -> string -> string
val uncompress : string -> string
```

And you can compile this program with:

    ocamlbuild -use-ocamlfind bin/easy.native

But keep in your  mind,  it's  an  easy  example  and  it's  not optimized for a
productive environment - so, don't copy/past and think.

## Build Requirements

 * OCaml >= 4.02.0
 * `base-bytes` meta-package
 * Bigarray module (provided by the standard library of OCaml)
 * `topkg` and `ocamlfind` to build the project

With you want to compile the test program, you need:

 * `camlzip` to compare `decompress` with `zlib`
 * `re`
 * `alcotest`
