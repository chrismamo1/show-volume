open Humane_re
open Textutils.Std

let mute_icon = "🔇";;
let speaker_icon = "🔈";;
let solid_rect = "▰";;
let outline_rect = "▱";;

let parse_pactl lines =
  let sinks =
    lines
    |> Str.(find_matches (regexp "Sink #.*\n\\(\t+.*\n\\)+")) in
  let states =
    List.map Str.(find_matches (regexp "State: \\(.*\\)\n")) sinks in
  let volumes =
    List.map Str.(find_matches (regexp "\tVolume: \\(.*\\)\n")) sinks (* gets the raw volume strings *)
    |> List.flatten
    |> List.map
        (fun str ->
          try
            Scanf.(sscanf
                    str
                    "\tVolume: front-left: %d / %d%% / %f dB, front-right: %d / %d%% / %f dB"
                    (fun _ a _ _ b _ -> a,b))
          with | exn -> 0, 0)
  in
  List.map2 (fun a b -> a,b) states volumes;;

let color_to_string = function
  | `Red -> "#ff0000"
  | `Green -> "#00ff00"
  | `Yellow -> "#ffff00"

let () =
  let utf8 = ref false in
  let colored = ref false in
  let i3bar = ref false in
  let n = ref 0 in
  let speclist =
    [ "-utf8", Arg.Set utf8, "Enables prettified UTF-8 output.";
      "-colored", Arg.Set colored, "Enables colorful output using JSC's Console.Ansi.";
      "-i3bar", Arg.Set i3bar, "Enables output to be formatted in a way that is intended to be read by the i3bar.";
      "-sink", Arg.Set_int n, "Specifies which sink to output data for."; ] in
  let usage_msg = "show-volume is a tool to show the current volume of the active \
                   device in the terminal, intended for use with the i3 window \
                   manager panel. Options:" in
  Arg.parse speclist print_endline usage_msg;
  while true do
    let is = Unix.open_process_in "pactl list sinks" in
    let lines = ref "" in
    try
      while true do
        lines := !lines ^ input_line is;
        lines := !lines ^ "\n";
      done
    with | End_of_file -> close_in is;
    let sinks = parse_pactl !lines in
    let sink = List.nth sinks !n in
    let stat,vol = sink in
    let icon = if fst vol > 0 then speaker_icon else mute_icon in
    let icon_color =
      if fst vol = 0 then `Red
      else begin
        if fst vol <= 29 then `Yellow else `Green
      end
    in
    let indicator =
      if !utf8 then begin
        let s = ref "" in
        let () = for i = 1 to (fst vol) / 10 do
            s := !s ^ solid_rect;
          done in
        let () = for i = 1 to 10 - (fst vol) / 10 do
            s := !s ^ outline_rect;
          done in
        !s
      end
      else Printf.sprintf "%d%%" (fst vol)
    in
    let main_color = if fst vol <= 20 then `Yellow else `Green in
    let icon_printer =
      if !colored
      then Console.Ansi.(output_string [icon_color] stdout)
      else output_string stdout in
    let indicator_printer =
      if !colored
      then Console.Ansi.(output_string [indicator_color] stdout)
      else output_string stdout in
    begin match !i3bar with
    | false ->
          Printf.(printf "Sink #%d " !n);
          if !utf8
          then begin
            icon_printer icon;
            indicator_printer indicator;
          end
          else indicator_printer indicator;
          output_string stdout "\r";
    | true ->
        let fulltext = Printf.sprintf "Sink #%d: %s%s" !n icon indicator in
        let output = Yojson.Basic.(
            `List [
              `Assoc [
                "name", `String "volume";
                "instance", `String (string_of_int !n);
                "full_text", `String fulltext;
                "color", `String (color_to_string icon_color);
              ]
            ]
          ) in
        output_string stdout (Yojson.Basic.to_string output ^ "\n");
    end;
    flush_all ();
    Unix.sleep 1;
  done;
