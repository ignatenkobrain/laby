let conf_tags =
  Conf.string
    (F.x "theme" [])

let conf_format_tags =
  Conf.list ~p:(conf_tags#plug "format")
    (F.x "format theme" [])

let env_term =
  begin try Some (Sys.getenv "TERM") with Not_found -> None end

let lang =
  begin try Sys.getenv "LC_MESSAGES" with Not_found ->
    begin try Sys.getenv "LC_ALL" with Not_found ->
      begin try Sys.getenv "LANG" with Not_found ->
	""
      end
    end
  end

let escape c s = "\027[" ^ c ^ "m" ^ s ^ "\027[0m"

let color, bcolor =
  begin match env_term with
  | Some ("xterm" | "xterm-color") ->
      let c r g b = string_of_int (16+b+6*g+36*r) in
      (fun r g b -> "38;5;" ^ c r g b), (fun r g b -> "48;5;" ^ c r g b)
  | Some ("rxvt-unicode" | "rxvt") ->
      let c r g b = string_of_int (16+(b*3/5)+4*(g*3/5)+16*(r*3/5)) in
      (fun r g b -> "38;5;" ^ c r g b), (fun r g b -> "48;5;" ^ c r g b)
  | _ ->
      (fun r g b -> "0"), (fun r g b -> "0")
  end

let codes =
  let is_digit c = '0' <= c && c <= '5' in
  let digit c = int_of_char c - int_of_char '0' in
  let unrecognized str =
(*     error (F.x "unrecognized value <val>" ["val", F.string str]); *)
    ""
  in
  begin function
  | "" -> ""
  | "bold" -> "01" | "italic" -> "03" | "underline" -> "04"
  | "#black" -> "30" | "##black" -> "40"
  | "#red" -> "31" | "##red" -> "41"
  | "#green" -> "32" | "##green" -> "42"
  | "#yellow" -> "33" | "##yellow" -> "43"
  | "#blue" -> "34" | "##blue" -> "44"
  | "#purple" -> "35" | "##purple" -> "45"
  | "#cyan" -> "36" | "##cyan" -> "46"
  | "#white" -> "37" | "##white" -> "47"
  | str when str.[0] = '#' ->
      if String.length str = 4 &&
	is_digit str.[1] && is_digit str.[2] && is_digit str.[3]
      then color (digit str.[1]) (digit str.[2]) (digit str.[3])
      else if String.length str = 5 && str.[1] = '#'
	&& is_digit str.[2] && is_digit str.[3] && is_digit str.[4]
      then bcolor (digit str.[2]) (digit str.[3]) (digit str.[4])
      else unrecognized str
  | str -> unrecognized str
  end

let tag s descr =
  let c =
    begin try Conf.list ~p:(conf_tags#plug s) ~d:[] descr
    with
    | Conf.Unbound _ ->
	Printf.printf "name: %s%!\n" s; assert false
    end
  in
  let tstr = ref None in
  let tag m =
    if !tstr = None then
      tstr := Some (String.concat ";" (List.map codes c#get));
    begin match !tstr with
    | Some tstr when tstr <> "" -> escape tstr m
    | _ -> m
    end
  in
  F.t tag

let load_theme s =
  Conf.conf_file ~strict:false conf_tags#ut s

let tag_quoted = tag "format-quoted" (F.s "quote style")
let tag_label = tag "format-label" F.n

let tag_msg_unknown = tag "format-msg-unknown" F.n
let tag_msg_lang = tag "format-msg-lang" F.n
let tag_msg_bad = tag "format-msg-bad" F.n

let texts : (string, (string * F.t) list -> F.t) Hashtbl.t =
  Hashtbl.create 1024

let texts_line txt str =
  let msg_lang = ref "" in
  let elem = ref "" in
  let arg = ref "" in
  let l = ref [] in
  let push c str = str := !str ^ String.make 1 c in
  let add_elem () = l := !l @ [ `Elem !elem ]; elem := "" in
  let add_arg () = l := !l @ [ `Arg !arg ]; arg := "" in
  let p = ref 0 in
  let eos = String.length str in
  let state = ref `Init in
  while !p < eos do
    state :=
      begin match !state, str.[!p] with
      | `Init, '\t' ->
	  while str.[!p] = '\t' do incr p done;
	  if !msg_lang = "text" then (txt := ""; `Text) else `Elem
      | `Init, ' ' -> `Error
      | `Init, c -> push c msg_lang; incr p; `Init
      | `Text, '\n' -> incr p; `Text
      | `Text, c -> incr p; push c txt; `Text
      | `Elem, '<' -> incr p; add_elem (); `Arg
      | `Elem, '\n' -> incr p; add_elem (); `Elem
      | `Elem, c -> push c elem; incr p; `Elem
      | `Arg, '>' -> incr p; add_arg (); `Elem
      | `Arg, '\n' -> `Error
      | `Arg, c -> push c arg; incr p; `Arg
      | `Error, _ -> p := eos; `Error
      end
  done;
  let msg vars =
    let map =
      begin function
      | `Elem e -> F.s e
      | `Arg a ->
	  begin try List.assoc a vars with
	  | Not_found -> tag_msg_unknown (F.s "<?>")
	  end
      end
    in
    let msg = F.h ~sep:F.n (List.map map !l) in
    if !msg_lang = lang then msg
    else F.h [tag_msg_lang (F.s ("<" ^ !msg_lang ^ ">")); msg]
  in
  begin match !state with
  | `Text -> `Skip
  | `Elem -> `Entry (!msg_lang, !txt, msg)
  | _ ->
      if (str <> "\n" && str.[0] <> '#') then `Error else `Skip
  end

let bad m vars =
  let arg (var, fn) = F.h [tag_msg_bad (F.s (var ^ ":")); fn] in
  let fn vars =
    F.h [tag_msg_bad (F.s "<!>"); F.s m; F.v (List.map arg vars)]
  in
  Hashtbl.add texts m fn;
  fn vars


let string t =
  let rec str ?(ind="\n") ?(pri=100) ?(cr=true) t =
    let aux ?(ind=ind) ?(pri=pri) ?(cr=false) t = str ~ind ~pri ~cr t in
    begin match F.use t with
    | `N -> ""
    | `T (t, m) -> t (aux m)
    | `S (s) -> s
    | `L (s, m) -> aux (tag_label (F.s (s ^ ":"))) ^ " " ^ aux m
    | `H (sep0, l) ->
	let sl = List.map (fun x -> aux x) l in
	String.concat (aux sep0) sl
    | `V (head0, l) ->
	let ind0 = aux head0 in
	let ind = ind ^ ind0 in
	begin match l with
	| [] -> ""
	| x :: q ->
	    let tab =
	      String.concat ind (aux ~ind ~cr:true x :: List.map (aux ~ind ~cr:true) q)
	    in
	    if cr then ind0 ^ tab else ind ^ tab
	end
    | `Q l ->
	let ind = ind ^ "  " in
	ind ^ (aux ~ind l)
    | `P (pri0, wrap, m) ->
	let m' = if pri <= pri0 then wrap m else m in
	aux ~pri:pri0 m'
    | `X (mstr, vars) ->
	let t =
	  begin try
	      begin try (Hashtbl.find texts mstr) vars with
	      | Not_found ->
		  begin match texts_line (ref mstr) ("\t" ^ mstr ^ "\n") with
		  | `Entry (msg_lang, txt, msg) ->
	              Hashtbl.add texts txt msg; msg vars
		  | _ -> bad mstr vars
		  end
	      end
	    with
	    | Not_found -> bad mstr vars
	  end
	in
	aux t
    | `Int i -> string_of_int i
    | `Float f -> string_of_float f
    | `String s -> "\"" ^ aux (tag_quoted (F.s s)) ^ "\""
    | `Time time ->
	let date = Unix.localtime time in
	Printf.sprintf "%d/%02d/%02d %02d:%02d:%02d"
	  (date.Unix.tm_year+1900)
	  (date.Unix.tm_mon+1)
	  date.Unix.tm_mday
	  date.Unix.tm_hour
	  date.Unix.tm_min
	  date.Unix.tm_sec
    | `Exn e -> Printexc.to_string e
    | _ -> "<unknown>"
    end
  in
  str t

let stdout x =
  Printf.printf "%s\n" (string x)

let log : (int -> F.t -> unit) ref =
  ref (fun _ _ -> ())

let read_texts error file =
  let lnb = ref 0 in
  begin try
      let txt = ref "" in
      while true do
	let str = incr lnb; input_line file ^ "\n" in
	begin match texts_line txt str with
	| `Entry (msg_lang, txt, msg) ->
	    !log 5 (
	      F.x "msg txt: <txt> lang: <lang>" [
		"text", F.string txt;
		"lang:", F.string msg_lang;
	      ]
	    );
	    if lang = msg_lang then
	      Hashtbl.add texts txt msg
	| `Skip -> ()
	| `Error -> error !lnb (F.x "syntax error" [])
	end
      done
    with
    | End_of_file -> ()
  end

let error path line f =
  !log 2 (
    F.x "file <f>, line <l>: <error>" [
      "f", F.string path;
      "l", F.int line;
      "error", f
    ]
  )

let load_texts path =
  begin try
      let f = open_in_bin path in
      read_texts (error path) f;
      close_in f;
    with
    | Sys_error m ->
	!log 2 (F.x "open failed: <error>" ["error", F.string m]);
	!log 2 (F.x "failed to open texts file" []);
  end

let tag_cmd_output = tag "cmd-output" (F.s "command line output")
let tag_cmd_input = tag "cmd-input" (F.s "command line input")

let output f =
(*   let head = tag_cmd_output (F.s "·") in *)
  stdout (F.v ~head:(F.h ~sep:F.n [tag_cmd_output (F.s ">"); F.s " "]) [f]);
  stdout F.n

let input () =
  let prompt = F.h [tag_cmd_input (F.s "<"); F.s ""] in
  print_string (string prompt);
  begin try Some (read_line ()) with
  | End_of_file -> None
  end

let exn e =
  stdout (F.h [F.h ~sep:F.n [F.x "exception" []; F.s ":"]; F.q (F.exn e)])
