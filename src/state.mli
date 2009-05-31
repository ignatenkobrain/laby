
(*
 * Copyright (C) 2007-2009 The laby team
 * You have permission to copy, modify, and redistribute under the
 * terms of the GPL-3.0. For full license terms, see gpl-3.0.txt.
 *)

type tile = [ `Void | `Wall | `Exit | `Rock | `Web | `NRock | `NWeb ]
type dir = [ `N | `E | `S | `W ]

type action =
 [ `None | `Start
 | `Wall_In | `Rock_In | `Exit_In | `Web_In
 | `Web_Out
 | `Exit | `No_Exit | `Carry_Exit
 | `Rock_Take | `Rock_Drop
 | `Rock_No_Take | `Rock_No_Drop
 ]

type t

val make : tile array array -> int * int -> dir -> t
val copy : t -> t
val init : t -> t

val run : string -> t -> string * t

val iter_map : t -> (int -> int -> tile -> unit) -> unit
val pos : t -> int * int
val carry : t -> [`None | `Rock ]
val dir : t -> dir
val action : t -> action

