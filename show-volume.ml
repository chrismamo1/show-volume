open Humane_re
open Textutils.Std
open Lwt.Infix

type conf = {
  utf8: bool;
  colored: bool;
  i3bar: bool;
  n: int }

let mute_icon = "🔇";;
let speaker_icon = "🔈";;
let solid_rect = "▰";;
let outline_rect = "▱";;

let parse_pactl =
  (* prebuilding regular expressions for performance *)
  let sinks_matcher = Str.regexp "Sink #.*\n\\(\t+.*\n\\)+" in
  let states_matcher = Str.regexp "State: \\(.*\\)\n" in
  let volumes_matcher = Str.regexp "\tVolume: \\(.*\\)\n" in
  fun lines ->
    let sinks =
      lines
      |> Str.(find_matches sinks_matcher) in
    let states =
      List.map Str.(find_matches states_matcher) sinks in
    let volumes =
      List.map Str.(find_matches volumes_matcher) sinks (* gets the raw volume strings *)
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

let rec read_volume ?(count = 0) nsink old_state =
  let count = count + 1 in
  let cmd = "", [|"pactl"; "list"; "sinks"|] in
  Lwt_process.pread cmd
  >>= fun lines ->
  let sinks = parse_pactl lines in
  let sink = List.nth sinks nsink in
  match old_state with
  | None -> Lwt.return sink
  | Some v when count > 100 -> Lwt.return v (* so that overflow may be avoided *)
  | Some v ->
      if v = sink
      then Lwt_unix.sleep 0.125 >>= fun () -> read_volume ~count nsink old_state
      else Lwt.return sink

let rec main ({utf8; colored; i3bar; n} as cfg) old_state = begin
  read_volume n old_state
  >>= fun (stat, vol) ->
  let icon = if fst vol > 0 then speaker_icon else mute_icon in
  let icon_color =
    if fst vol = 0 then `Red
    else begin
      if fst vol <= 29 then `Yellow else `Green
    end
  in
  let indicator =
    if utf8 then begin
      let open CamomileLibrary in let open UPervasives in
      let ch = Scanf.sscanf (escaped_utf8 solid_rect) "\\u%x" (fun x -> x) in
      let ch' = Scanf.sscanf (escaped_utf8 outline_rect) "\\u%x" (fun x -> x) in
      UTF8.init 10 (fun i ->
        uchar_of_int (if i < (fst vol) / 10 then ch else ch'))
    end
    else Printf.sprintf "% 3d%%  " (fst vol)
  in
  let indicator_color = if fst vol <= 20 then `Yellow else `Green in
  let icon_printer =
    if colored
    then Console.Ansi.(output_string [icon_color] stdout)
    else output_string stdout in
  let indicator_printer =
    if colored
    then Console.Ansi.(output_string [indicator_color] stdout)
    else output_string stdout in
  begin match i3bar with
  | false ->
        Printf.(printf "Sink #%d " n);
        if utf8
        then begin
          icon_printer icon;
          indicator_printer indicator;
        end
        else indicator_printer indicator;
        output_string stdout "\r";
  | true ->
      let fulltext = Printf.sprintf "Sink #%d: %s%s" n icon indicator in
      let output = Yojson.Basic.(
          `List [
            `Assoc [
              "name", `String "volume";
              "instance", `String (string_of_int n);
              "full_text", `String fulltext;
              "color", `String (color_to_string icon_color);
            ]
          ]
        ) in
      output_string stdout (Yojson.Basic.to_string output ^ "\n");
  end;
  flush_all ();
  main cfg (Some (stat,vol)); (* pretty sure this is a tailcall *)
end

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
  let _ = Arg.parse speclist print_endline usage_msg in
  let utf8, colored, i3bar, n = !utf8, !colored, !i3bar, !n in
  Lwt_main.run (main {utf8; colored; i3bar; n} None)
