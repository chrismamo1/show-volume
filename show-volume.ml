open Humane_re
open Textutils.Std
open Lwt.Infix

type conf = {
  utf8: bool;
  colored: bool;
  i3bar: bool;
  n: int;
  volume_provider: (module DataSources.VolumeProvider) }

let mute_icon = "🔇";;
let speaker_icon = "🔈";;
let solid_rect = "▰";;
let outline_rect = "▱";;

let color_to_string = function
  | `Red -> "#ff0000"
  | `Green -> "#00ff00"
  | `Yellow -> "#ffff00"

let rec main ({utf8; colored; i3bar; n; volume_provider} as cfg) old_state = begin
  let (module Data) = volume_provider in
  Data.read_volume
    (`Sink (Data.sink_of_int n))
    old_state
  >>= fun ({status = stat; volume = [| vol_lft; vol_rgt |] }) ->
  let icon = if vol_lft > 0 then speaker_icon else mute_icon in
  let icon_color =
    if vol_lft = 0 then `Red
    else begin
      if vol_lft <= 29 then `Yellow else `Green
    end
  in
  let indicator =
    match utf8, vol_lft with
    | true, v when v = 0 -> ""
    | true, _ ->
      let open CamomileLibrary in let open UPervasives in
      let ch = Scanf.sscanf (escaped_utf8 solid_rect) "\\u%x" (fun x -> x) in
      let ch' = Scanf.sscanf (escaped_utf8 outline_rect) "\\u%x" (fun x -> x) in
      UTF8.init 10 (fun i ->
        uchar_of_int (if i < (vol_lft) / 10 then ch else ch'))
    | false, _ ->
        Printf.sprintf "% 3d%%  " (vol_lft)
  in
  let indicator_color = if vol_lft <= 20 then `Yellow else `Green in
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
  main cfg (Some {status = stat; volume = [|vol_lft; vol_rgt|]}); (* pretty sure this is a tailcall *)
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
  let open DataSources in
  let volume_provider = (module FilthyPulse : VolumeProvider) in
  (* FilthyPulse is the only supported data source at the moment *)
  Lwt_main.run (main {utf8; colored; i3bar; n; volume_provider} None)
