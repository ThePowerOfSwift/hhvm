(**
 * Copyright (c) 2015, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the "hack" directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 *
 *)

open Core
open Ide_api_types
open String_utils
open Sys_utils

module TNBody       = Typing_naming_body

(*****************************************************************************)
(* Types, constants *)
(*****************************************************************************)

type mode =
  | Ai of Ai_options.t
  | Autocomplete
  | Ffp_autocomplete
  | Color
  | Coverage
  | Dump_symbol_info
  | Dump_inheritance
  | Errors
  | AllErrors
  | Lint
  | Suggest
  | Dump_deps
  | Identify_symbol of int * int
  | Find_local of int * int
  | Outline
  | Find_refs of int * int
  | Highlight_refs of int * int
  | Decl_compare
  | Infer_return_types

type options = {
  filename : string;
  mode : mode;
  no_builtins : bool;
  tcopt : GlobalOptions.t;
}

let builtins_filename =
  Relative_path.create Relative_path.Dummy "builtins.hhi"

let builtins =
  "<?hh // decl\n"^
  "interface Traversable<+Tv> {}\n"^
  "interface Container<+Tv> extends Traversable<Tv> {}\n"^
  "interface Iterator<+Tv> extends Traversable<Tv> {}\n"^
  "interface Iterable<+Tv> extends Traversable<Tv> {}\n"^
  "interface KeyedTraversable<+Tk, +Tv> extends Traversable<Tv> {}\n"^
  "interface KeyedContainer<+Tk, +Tv> extends Container<Tv>, KeyedTraversable<Tk,Tv> {}\n"^
  "interface KeyedIterator<+Tk, +Tv> extends KeyedTraversable<Tk, Tv>, Iterator<Tv> {}\n"^
  "interface KeyedIterable<Tk, +Tv> extends KeyedTraversable<Tk, Tv>, Iterable<Tv> {}\n"^
  "interface Awaitable<+T> {"^
  "  public function getWaitHandle(): WaitHandle<T>;"^
  "}\n"^
  "interface WaitHandle<+T> extends Awaitable<T> {}\n"^
  "interface ConstVector<+Tv> extends KeyedIterable<int, Tv>, KeyedContainer<int, Tv>{"^
  "  public function map<Tu>((function(Tv): Tu) $callback): ConstVector<Tu>;"^
  "}\n"^
  "interface ConstSet<+Tv> extends KeyedIterable<mixed, Tv>, Container<Tv>{}\n"^
  "interface ConstMap<Tk, +Tv> extends KeyedIterable<Tk, Tv>, KeyedContainer<Tk, Tv>{"^
  "  public function map<Tu>((function(Tv): Tu) $callback): ConstMap<Tk, Tu>;"^
  "  public function mapWithKey<Tu>((function(Tk, Tv): Tu) $fn): ConstMap<Tk, Tu>;"^
  "}\n"^
  "final class Vector<Tv> implements ConstVector<Tv>{\n"^
  "  public function map<Tu>((function(Tv): Tu) $callback): Vector<Tu>;\n"^
  "  public function filter((function(Tv): bool) $callback): Vector<Tv>;\n"^
  "  public function reserve(int $sz): void;"^
  "  public function add(Tv $value): Vector<Tv>;"^
  "  public function addAll(?Traversable<Tv> $it): Vector<Tv>;"^
  "}\n"^
  "final class ImmVector<+Tv> implements ConstVector<Tv> {"^
  "  public function map<Tu>((function(Tv): Tu) $callback): ImmVector<Tu>;"^
  "}\n"^
  "final class Map<Tk, Tv> implements ConstMap<Tk, Tv> {"^
  "  /* HH_FIXME[3007]: This is intentional; not a constructor */"^
  "  public function map<Tu>((function(Tv): Tu) $callback): Map<Tk, Tu>;"^
  "  public function mapWithKey<Tu>((function(Tk, Tv): Tu) $fn): Map<Tk, Tu>;"^
  "  public function contains<Tu super Tk>(Tu $k): bool;"^
  "}\n"^
  "final class ImmMap<Tk, +Tv> implements ConstMap<Tk, Tv>{"^
  "  public function map<Tu>((function(Tv): Tu) $callback): ImmMap<Tk, Tu>;"^
  "  public function mapWithKey<Tu>((function(Tk, Tv): Tu) $fn): ImmMap<Tk, Tu>;"^
  "}\n"^
  "final class StableMap<Tk, Tv> implements ConstMap<Tk, Tv> {"^
  "  public function map<Tu>((function(Tv): Tu) $callback): StableMap<Tk, Tu>;"^
  "  public function mapWithKey<Tu>((function(Tk, Tv): Tu) $fn): StableMap<Tk, Tu>;"^
  "}\n"^
  "final class Set<Tv> implements ConstSet<Tv> {}\n"^
  "final class ImmSet<+Tv> implements ConstSet<Tv> {}\n"^
  "class Exception {"^
  "  public function __construct(string $x) {}"^
  "  public function getMessage(): string;"^
  "}\n"^
  "class Generator<Tk, +Tv, -Ts> implements KeyedIterator<Tk, Tv> {\n"^
  "  public function next(): void;\n"^
  "  public function current(): Tv;\n"^
  "  public function key(): Tk;\n"^
  "  public function rewind(): void;\n"^
  "  public function valid(): bool;\n"^
  "  public function send(?Ts $v): void;\n"^
  "}\n"^
  "final class Pair<+Tk, +Tv> implements KeyedContainer<int,mixed> {public function isEmpty(): bool {}}\n"^
  "interface Stringish {public function __toString(): string {}}\n"^
  "interface XHPChild {}\n"^
  "function hh_show($val) {}\n"^
  "function hh_show_env() {}\n"^
  "interface Countable { public function count(): int; }\n"^
  "interface AsyncIterator<+Tv> {}\n"^
  "interface AsyncKeyedIterator<+Tk, +Tv> extends AsyncIterator<Tv> {}\n"^
  "class AsyncGenerator<Tk, +Tv, -Ts> implements AsyncKeyedIterator<Tk, Tv> {\n"^
  "  public function next(): Awaitable<?(Tk, Tv)> {}\n"^
  "  public function send(?Ts $v): Awaitable<?(Tk, Tv)> {}\n"^
  "  public function raise(Exception $e): Awaitable<?(Tk, Tv)> {}"^
  "}\n"^
  "function isset($x): bool;"^
  "function empty($x): bool;"^
  "function unset($x): void;"^
  "namespace HH {\n"^
  "abstract class BuiltinEnum<T> {\n"^
  "  final public static function getValues(): array<string, T>;\n"^
  "  final public static function getNames(): array<T, string>;\n"^
  "  final public static function coerce(mixed $value): ?T;\n"^
  "  final public static function assert(mixed $value): T;\n"^
  "  final public static function isValid(mixed $value): bool;\n"^
  "  final public static function assertAll(Traversable<mixed> $values): Container<T>;\n"^
  "}\n"^
  "}\n"^
  "function array_map($x, $y, ...);\n"^
  "function idx<Tk, Tv>(?KeyedContainer<Tk, Tv> $c, $i, $d = null) {}\n"^
  "final class stdClass {}\n" ^
  "function rand($x, $y): int;\n" ^
  "function invariant($x, ...): void;\n" ^
  "function exit(int $exit_code_or_message = 0): noreturn;\n" ^
  "function invariant_violation(...): noreturn;\n" ^
  "function get_called_class(): string;\n" ^
  "abstract final class Shapes {\n" ^
  "  public static function idx(shape(...) $shape, arraykey $index, $default = null) {}\n" ^
  "  public static function keyExists(shape(...) $shape, arraykey $index): bool {}\n" ^
  "  public static function removeKey(shape(...) $shape, arraykey $index): void {}\n" ^
  "  public static function toArray(shape(...) $shape): array<arraykey, mixed> {}\n" ^
  "}\n" ^
  "newtype typename<+T> as string = string;\n"^
  "newtype classname<+T> as typename<T> = typename<T>;\n" ^
 "function var_dump($x): void;\n" ^
  "function gena();\n" ^
  "function genva();\n" ^
  "function gen_array_rec();\n"^
  "function is_int(mixed $x): bool {}\n"^
  "function is_bool(mixed $x): bool {}\n"^
  "function is_float(mixed $x): bool {}\n"^
  "function is_string(mixed $x): bool {}\n"^
  "function is_null(mixed $x): bool {}\n"^
  "function is_array(mixed $x): bool {}\n"^
  "function is_vec(mixed $x): bool {}\n"^
  "function is_dict(mixed $x): bool {}\n"^
  "function is_keyset(mixed $x): bool {}\n"^
  "function is_resource(mixed $x): bool {}\n"^
  "interface IMemoizeParam {\n"^
  "  public function getInstanceKey(): string;\n"^
  "}\n"^
  "newtype TypeStructure<T> as shape(\n"^
  "  'kind'=> int,\n"^
  "  'nullable'=>?bool,\n"^
  "  'classname'=>?classname<T>,\n"^
  "  'elem_types' => ?array,\n"^
  "  'param_types' => ?array,\n"^
  "  'return_type' => ?array,\n"^
  "  'generic_types' => ?array,\n"^
  "  'fields' => ?array,\n"^
  "  'name' => ?string,\n"^
  "  'alias' => ?string,\n"^
  ") = shape(\n"^
  "  'kind'=> int,\n"^
  "  'nullable'=>?bool,\n"^
  "  'classname'=>?classname<T>,\n"^
  "  'elem_types' => ?array,\n"^
  "  'param_types' => ?array,\n"^
  "  'return_type' => ?array,\n"^
  "  'generic_types' => ?array,\n"^
  "  'fields' => ?array,\n"^
  "  'name' => ?string,\n"^
  "  'alias' => ?string,\n"^
  ");\n"^
  "function type_structure($x, $y);\n"^
  "const int __LINE__ = 0;\n"^
  "const string __CLASS__ = '';\n"^
  "const string __TRAIT__ = '';\n"^
  "const string __FILE__ = '';\n"^
  "const string __DIR__ = '';\n"^
  "const string __FUNCTION__ = '';\n"^
  "const string __METHOD__ = '';\n"^
  "const string __NAMESPACE__ = '';\n"^
  "interface Indexish<+Tk, +Tv> extends KeyedContainer<Tk, Tv> {}\n"^
  "abstract final class dict<+Tk, +Tv> implements Indexish<Tk, Tv> {}\n"^
  "function dict<Tk, Tv>(KeyedTraversable<Tk, Tv> $arr): dict<Tk, Tv> {}\n"^
  "abstract final class keyset<+T as arraykey> implements Indexish<T, T> {}\n"^
  "abstract final class vec<+Tv> implements Indexish<int, Tv> {}\n"^
  "function meth_caller(string $cls_name, string $meth_name);\n"^
  "namespace HH\\Asio {"^
  "  function va(...$args);\n"^
  "}\n"^
  "function hh_log_level(int $level) {}\n"

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let die str =
  let oc = stderr in
  output_string oc str;
  close_out oc;
  exit 2

let error ?(indent=false) l =
  output_string stderr (Errors.to_string ~indent (Errors.to_absolute l))

let parse_options () =
  let fn_ref = ref None in
  let usage = Printf.sprintf "Usage: %s filename\n" Sys.argv.(0) in
  let mode = ref Errors in
  let no_builtins = ref false in
  let line = ref 0 in
  let set_mode x () =
    if !mode <> Errors
    then raise (Arg.Bad "only a single mode should be specified")
    else mode := x in
  let set_ai x = set_mode (Ai (Ai_options.prepare ~server:false x)) () in
  let safe_array = ref false in
  let safe_vector_array = ref false in
  let options = [
    "--ai",
      Arg.String (set_ai),
    " Run the abstract interpreter";
    "--all-errors",
      Arg.Unit (set_mode AllErrors),
      " List all errors not just the first one";
    "--auto-complete",
      Arg.Unit (set_mode Autocomplete),
      " Produce autocomplete suggestions";
    "--ffp-auto-complete",
      Arg.Unit (set_mode Ffp_autocomplete),
      " Produce autocomplete suggestions using the full-fidelity parse tree";
    "--colour",
      Arg.Unit (set_mode Color),
      " Produce colour output";
    "--color",
      Arg.Unit (set_mode Color),
      " Produce color output";
    "--coverage",
      Arg.Unit (set_mode Coverage),
      " Produce coverage output";
    "--dump-symbol-info",
      Arg.Unit (set_mode Dump_symbol_info),
      " Dump all symbol information";
    "--lint",
      Arg.Unit (set_mode Lint),
      " Produce lint errors";
    "--suggest",
      Arg.Unit (set_mode Suggest),
      " Suggest missing typehints";
    "--no-builtins",
      Arg.Set no_builtins,
      " Don't use builtins (e.g. ConstSet)";
    "--dump-deps",
      Arg.Unit (set_mode Dump_deps),
      " Print dependencies";
    "--dump-inheritance",
      Arg.Unit (set_mode Dump_inheritance),
      " Print inheritance";
    "--identify-symbol",
      Arg.Tuple ([
        Arg.Int (fun x -> line := x);
        Arg.Int (fun column -> set_mode (Identify_symbol (!line, column)) ());
      ]),
      "<pos> Show info about symbol at given line and column";
    "--find-local",
      Arg.Tuple ([
        Arg.Int (fun x -> line := x);
        Arg.Int (fun column -> set_mode (Find_local (!line, column)) ());
      ]),
      "<pos> Find all usages of local at given line and column";
    "--outline",
      Arg.Unit (set_mode Outline),
      " Print file outline";
    "--find-refs",
      Arg.Tuple ([
        Arg.Int (fun x -> line := x);
        Arg.Int (fun column -> set_mode (Find_refs (!line, column)) ());
      ]),
      "<pos> Find all usages of a symbol at given line and column";
    "--highlight-refs",
      Arg.Tuple ([
        Arg.Int (fun x -> line := x);
        Arg.Int (fun column -> set_mode (Highlight_refs (!line, column)) ());
      ]),
      "<pos> Highlight all usages of a symbol at given line and column";
    "--decl-compare",
      Arg.Unit (set_mode Decl_compare),
      " Test comparison functions used in incremental mode on declarations" ^
      " in provided file";
    "--safe_array",
      Arg.Set safe_array,
      " Enforce array subtyping relationships so that array<T> and array<Tk, \
      Tv> are each subtypes of array but not vice-versa.";
    "--safe_vector_array",
      Arg.Set safe_vector_array,
      " Enforce array subtyping relationships so that array<T> is not a \
      of array<int, T>.";
    "--infer-return-types",
      Arg.Unit (set_mode Infer_return_types),
      " Infers return types of functions and methods."
  ] in
  let options = Arg.align ~limit:25 options in
  Arg.parse options (fun fn -> fn_ref := Some fn) usage;
  let fn = match !fn_ref with
    | Some fn -> fn
    | None -> die usage in
  let tcopt = {
    GlobalOptions.default with
      GlobalOptions.tco_safe_array = !safe_array;
      GlobalOptions.tco_safe_vector_array = !safe_vector_array;
  } in
  { filename = fn;
    mode = !mode;
    no_builtins = !no_builtins;
    tcopt;
  }

let infer_return tcopt fn { FileInfo.funs; classes; typedefs; consts; _ } =
  let make_set =
    List.fold_left ~f: (fun acc (_, x) -> SSet.add x acc) ~init: SSet.empty
  in
  let n_funs = make_set funs in
  let n_classes = make_set classes in
  let n_types = make_set typedefs in
  let n_consts = make_set consts in
  let names = { FileInfo.n_funs; n_classes; n_types; n_consts } in
  let fast = Relative_path.Map.singleton fn names in
  let inferred_types =
    Typing_suggest_service.suggest_files
      tcopt (Typing_suggest_service.keys fast)
  in
  let funs_and_methods = !Typing_suggest.funs_and_methods in
  let () = Typing_suggest.funs_and_methods := [] in
  let funs_and_methods =
    List.filter
      ~f:(fun (pos, _) -> Relative_path.Map.mem fast (Pos.filename pos))
      funs_and_methods
  in
  let inferred_types =
    List.filter
      ~f:(fun (_, pos, kind, _) ->
        (Relative_path.Map.mem fast (Pos.filename pos))
        && (kind == Typing_suggest.Kreturn))
      inferred_types
  in
  let inferred_types =
    List.sort
      ~cmp: (fun (_, p1, _, _) (_ , p2, _, _) -> Pos.compare p1 p2)
      inferred_types
  in
  let funs_and_methods =
    List.sort
      ~cmp: (fun (p1, _) (p2, _) -> Pos.compare p1 p2) funs_and_methods
  in
  let rec print_returns_with_funs ts fs  =
    match ts, fs with
    | [], _
    | _, [] -> ()
    | (tenv, p1, _, ty) :: ts_, (p2, id) :: fs_ ->
      begin match Pos.compare p1 p2 with
        | 0 -> Printf.printf "%s : %s \n" id (Typing_print.full tenv ty);
               print_returns_with_funs ts_ fs_
        | x when x > 0 -> print_returns_with_funs ts_ fs
        | _ -> print_returns_with_funs ts fs_
      end
in
print_returns_with_funs inferred_types funs_and_methods

let suggest_and_print tcopt fn { FileInfo.funs; classes; typedefs; consts; _ } =
  let make_set =
    List.fold_left ~f: (fun acc (_, x) -> SSet.add x acc) ~init: SSet.empty
  in
  let n_funs = make_set funs in
  let n_classes = make_set classes in
  let n_types = make_set typedefs in
  let n_consts = make_set consts in
  let names = { FileInfo.n_funs; n_classes; n_types; n_consts } in
  let fast = Relative_path.Map.singleton fn names in
  let patch_map = Typing_suggest_service.go None fast tcopt in
  match Relative_path.Map.get patch_map fn with
    | None -> ()
    | Some l -> begin
      (* Sort so that the unit tests come out in a consistent order, normally
       * doesn't matter. *)
      let l = List.sort ~cmp: (fun (x, _, _) (y, _, _) -> x - y) l
      in
      List.iter ~f: (ServerConvert.print_patch fn tcopt) l

    end

(* This allows one to fake having multiple files in one file. This
 * is used only in unit test files.
 * Indeed, there are some features that require mutliple files to be tested.
 * For example, newtype has a different meaning depending on the file.
 *)
let rec make_files = function
  | [] -> []
  | Str.Delim header :: Str.Text content :: rl ->
      let pattern = Str.regexp "////" in
      let header = Str.global_replace pattern "" header in
      let pattern = Str.regexp "[ ]*" in
      let filename = Str.global_replace pattern "" header in
      (filename, content) :: make_files rl
  | _ -> assert false

(* We have some hacky "syntax extensions" to have one file contain multiple
 * files, which can be located at arbitrary paths. This is useful e.g. for
 * testing lint rules, some of which activate only on certain paths. It's also
 * useful for testing abstract types, since the abstraction is enforced at the
 * file boundary.
 * Takes the path to a single file, returns a map of filenames to file contents.
 *)
let file_to_files file =
  let abs_fn = Relative_path.to_absolute file in
  let content = cat abs_fn in
  let delim = Str.regexp "////.*" in
  if Str.string_match delim content 0
  then
    let contentl = Str.full_split delim content in
    let files = make_files contentl in
    List.fold_left ~f: begin fun acc (sub_fn, content) ->
      let file =
        Relative_path.create Relative_path.Dummy (abs_fn^"--"^sub_fn) in
      Relative_path.Map.add acc ~key:file ~data:content
    end ~init: Relative_path.Map.empty files
  else if string_starts_with content "// @directory " then
    let contentl = Str.split (Str.regexp "\n") content in
    let first_line = List.hd_exn contentl in
    let regexp = Str.regexp ("^// @directory *\\([^ ]*\\) \
      *\\(@file *\\([^ ]*\\)*\\)?") in
    let has_match = Str.string_match regexp first_line 0 in
    assert has_match;
    let dir = Str.matched_group 1 first_line in
    let file_name =
      try
        Str.matched_group 3 first_line
      with
        Not_found -> abs_fn in
    let file = Relative_path.create Relative_path.Dummy (dir ^ file_name) in
    let content = String.concat "\n" (List.tl_exn contentl) in
    Relative_path.Map.singleton file content
  else
    Relative_path.Map.singleton file content

(* Make readable test output *)
let replace_color input =
  match input with
  | (Some Unchecked, str) -> "<unchecked>"^str^"</unchecked>"
  | (Some Checked, str) -> "<checked>"^str^"</checked>"
  | (Some Partial, str) -> "<partial>"^str^"</partial>"
  | (None, str) -> str

let print_colored fn type_acc =
  let content = cat (Relative_path.to_absolute fn) in
  let results = ColorFile.go content type_acc in
  if Unix.isatty Unix.stdout
  then Tty.cprint (ClientColorFile.replace_colors results)
  else print_string (List.map ~f: replace_color results |> String.concat "")

let print_coverage fn type_acc =
  let counts = ServerCoverageMetric.count_exprs fn type_acc in
  ClientCoverageMetric.go ~json:false (Some (Coverage_level.Leaf counts))

let check_errors opts errors files_info =
  Relative_path.Map.fold files_info ~f:begin fun fn fileinfo errors ->
    errors @ Errors.get_error_list
        (Typing_check_utils.check_defs opts fn fileinfo)
  end ~init:errors

let with_named_body opts n_fun =
  (** In the naming heap, the function bodies aren't actually named yet, so
   * we need to invoke naming here.
   * See also docs in Naming.Make. *)
  let n_f_body = TNBody.func_body opts n_fun in
  { n_fun with Nast.f_body = Nast.NamedBody n_f_body }

let n_fun_fold opts fn acc (_, fun_name) =
  match Parser_heap.find_fun_in_file ~full:true opts fn fun_name with
  | None -> acc
  | Some f ->
    let n_fun = Naming.fun_ opts f in
    (with_named_body opts n_fun) :: acc

let n_class_fold _tcopt _fn acc _class_name = acc
let n_type_fold _tcopt _fn acc _type_name = acc
let n_const_fold _tcopt _fn acc _const_name = acc

(** Load the Nast for the file from the Nast heaps. *)
let nast_for_file opts fn
{ FileInfo.funs; classes; typedefs; consts; _} =
  List.fold_left funs ~init:[] ~f:(n_fun_fold opts fn),
  List.fold_left classes ~init:[] ~f:(n_class_fold opts fn),
  List.fold_left typedefs ~init:[] ~f:(n_type_fold opts fn),
  List.fold_left consts ~init:[] ~f:(n_const_fold opts fn)

let parse_name_and_decl popt files_contents tcopt =
  Errors.do_ begin fun () ->
    let parsed_files =
      Relative_path.Map.mapi
       (Parser_hack.program popt) files_contents in

    let files_info =
      Relative_path.Map.mapi begin fun fn parsed_file ->
        let {Parser_hack.file_mode; comments; ast; _} = parsed_file in
        Parser_heap.ParserHeap.add fn (ast, Parser_heap.Full);
        let funs, classes, typedefs, consts = Ast_utils.get_defs ast in
        { FileInfo.
          file_mode; funs; classes; typedefs; consts; comments = Some comments;
        }
      end parsed_files in

    Relative_path.Map.iter files_info begin fun fn fileinfo ->
      let {FileInfo.funs; classes; typedefs; consts; _} = fileinfo in
      NamingGlobal.make_env popt ~funs ~classes ~typedefs ~consts
    end;

    Relative_path.Map.iter files_info begin fun fn _ ->
      Decl.make_env tcopt fn
    end;

    files_info
  end

let add_newline contents =
  let x = String.index contents '\n' in
  String.((sub contents 0 x) ^ "\n" ^ (sub contents x ((length contents) - x)))

let get_decls defs =
  SSet.fold (fun x acc -> (Decl_heap.Typedefs.find_unsafe x)::acc)
  defs.FileInfo.n_types
  [],
  SSet.fold (fun x acc -> (Decl_heap.Funs.find_unsafe x)::acc)
  defs.FileInfo.n_funs
  [],
  SSet.fold (fun x acc -> (Decl_heap.Classes.find_unsafe x)::acc)
  defs.FileInfo.n_classes
  []

let fail_comparison s =
  raise (Failure (
    (Printf.sprintf "Comparing %s failed!\n" s) ^
    "It's likely that you added new positions to decl types " ^
    "without updating Decl_pos_utils.NormalizeSig\n"
  ))

let compare_typedefs t1 t2 =
  let t1 = Decl_pos_utils.NormalizeSig.typedef t1 in
  let t2 = Decl_pos_utils.NormalizeSig.typedef t2 in
  if t1 <> t2 then fail_comparison "typedefs"

let compare_funs f1 f2 =
  let f1 = Decl_pos_utils.NormalizeSig.fun_type f1 in
  let f2 = Decl_pos_utils.NormalizeSig.fun_type f2 in
  if f1 <> f2 then fail_comparison "funs"

let compare_classes c1 c2 =
  if Decl_compare.class_big_diff c1 c2 then fail_comparison "class_big_diff";

  let c1 = Decl_pos_utils.NormalizeSig.class_type c1 in
  let c2 = Decl_pos_utils.NormalizeSig.class_type c2 in
  let _, is_unchanged =
    Decl_compare.ClassDiff.compare c1.Decl_defs.dc_name c1 c2 in
  if not is_unchanged then fail_comparison "ClassDiff";

  let _, is_unchanged = Decl_compare.ClassEltDiff.compare c1 c2 in
  if is_unchanged = `Changed then fail_comparison "ClassEltDiff"

let test_decl_compare filename popt files_contents tcopt files_info =
  (* skip some edge cases that we don't handle now... ugly! *)
  if (Relative_path.suffix filename) = "capitalization3.php" then () else
  if (Relative_path.suffix filename) = "capitalization4.php" then () else
  (* do not analyze builtins over and over *)
  let files_info = Relative_path.Map.remove files_info builtins_filename in

  let files = Relative_path.Map.fold files_info
    ~f:(fun k _ acc -> Relative_path.Set.add acc k)
    ~init:Relative_path.Set.empty
  in

  let defs = Relative_path.Map.fold files_info ~f:begin fun _ names1 names2 ->
      FileInfo.(merge_names (simplify names1) names2)
    end ~init:FileInfo.empty_names
  in

  let typedefs1, funs1, classes1 = get_decls defs in
  (* For the purpose of this test, we can ignore other heaps *)
  Parser_heap.ParserHeap.remove_batch files;

  (* We need to oldify, not remove, for ClassEltDiff to work *)
  Decl_redecl_service.oldify_type_decl
    None files_info ~bucket_size:1 FileInfo.empty_names defs
      ~collect_garbage:false;

  let files_contents = Relative_path.Map.map files_contents ~f:add_newline in
  let _, _, _ = parse_name_and_decl popt files_contents tcopt in

  let typedefs2, funs2, classes2 = get_decls defs in

  List.iter2_exn typedefs1 typedefs2 compare_typedefs;
  List.iter2_exn funs1 funs2 compare_funs;
  List.iter2_exn classes1 classes2 compare_classes;
  ()

let handle_mode mode filename opts popt files_contents files_info errors =
  match mode with
  | Ai _ -> ()
  | Autocomplete ->
      let file = cat (Relative_path.to_absolute filename) in
      let result =
        ServerAutoComplete.auto_complete opts file in
      List.iter ~f: begin fun r ->
        let open AutocompleteService in
        Printf.printf "%s %s\n" r.res_name r.res_ty
      end result
  | Ffp_autocomplete ->
      let file_text = cat (Relative_path.to_absolute filename) in
      (* TODO: Use a magic word/symbol to identify autocomplete location instead *)
      let args_regex = Str.regexp "AUTOCOMPLETE [1-9][0-9]* [0-9]*" in
      let (row, col) = try
        let _ = Str.search_forward args_regex file_text 0 in
        let raw_flags = Str.matched_string file_text in
        match split ' ' raw_flags with
        | [ _; row; column] -> (int_of_string row, int_of_string column)
        | _ -> failwith "Invalid test file: no flags found"
      with
        Not_found -> failwith "Invalid test file: no flags found"
      in
      let result =
        FfpAutocompleteService.auto_complete file_text (row, col)
      in begin
        match result with
        | [] -> Printf.printf "No result found\n"
        | res -> List.iter res ~f:begin fun r ->
            let open FfpAutocompleteService in
            Printf.printf "%s\n" r.name
          end
      end
  | Color ->
      Relative_path.Map.iter files_info begin fun fn fileinfo ->
        if fn = builtins_filename then () else begin
          let result = ServerColorFile.get_level_list begin fun () ->
            ignore @@ Typing_check_utils.check_defs opts fn fileinfo;
            fn
          end in
          print_colored fn result;
        end
      end
  | Coverage ->
      Relative_path.Map.iter files_info begin fun fn fileinfo ->
        if fn = builtins_filename then () else begin
          let type_acc =
            ServerCoverageMetric.accumulate_types fn fileinfo opts in
          print_coverage fn type_acc;
        end
      end
  | Dump_symbol_info ->
      begin match Relative_path.Map.get files_info filename with
        | Some fileinfo ->
            let raw_result =
              SymbolInfoService.helper opts [] [(filename, fileinfo)] in
            let result = SymbolInfoService.format_result raw_result in
            let result_json = ClientSymbolInfo.to_json result in
            print_endline (Hh_json.json_to_multiline result_json)
        | None -> ()
      end
  | Lint ->
      let lint_errors = Relative_path.Map.fold files_contents ~init:[]
        ~f:begin fun fn content lint_errors ->
          lint_errors @ fst (Lint.do_ begin fun () ->
            Linting_service.lint opts fn content
          end)
        end in
      if lint_errors <> []
      then begin
        let lint_errors = List.sort ~cmp: begin fun x y ->
          Pos.compare (Lint.get_pos x) (Lint.get_pos y)
        end lint_errors in
        let lint_errors = List.map ~f: Lint.to_absolute lint_errors in
        ServerLint.output_text stdout lint_errors;
        exit 2
      end
      else Printf.printf "No lint errors\n"
  | Dump_deps ->
    Relative_path.Map.iter files_info begin fun fn fileinfo ->
      ignore @@ Typing_check_utils.check_defs opts fn fileinfo
    end;
    Typing_deps.dump_deps stdout
  | Dump_inheritance ->
    Typing_deps.update_files files_info;
    Relative_path.Map.iter files_info begin fun fn fileinfo ->
      if fn = builtins_filename then () else begin
        List.iter fileinfo.FileInfo.classes begin fun (_p, class_) ->
          Printf.printf "Ancestors of %s and their overridden methods:\n"
            class_;
          let ancestors = MethodJumps.get_inheritance opts class_
            ~filter:MethodJumps.No_filter ~find_children:false files_info
            None in
          ClientMethodJumps.print_readable ancestors ~find_children:false;
          Printf.printf "\n";
        end;
        Printf.printf "\n";
        List.iter fileinfo.FileInfo.classes begin fun (_p, class_) ->
          Printf.printf "Children of %s and the methods they override:\n"
            class_;
          let children = MethodJumps.get_inheritance opts class_
            ~filter:MethodJumps.No_filter ~find_children:true files_info None in
          ClientMethodJumps.print_readable children ~find_children:true;
          Printf.printf "\n";
        end;
      end
    end;
  | Identify_symbol (line, column) ->
    let file = cat (Relative_path.to_absolute filename) in
    begin match ServerIdentifyFunction.go_absolute file line column opts with
      | [] -> print_endline "None"
      | result -> ClientGetDefinition.print_readable ~short_pos:true result
    end
  | Find_local (line, column) ->
    let file = cat (Relative_path.to_absolute filename) in
    let result = ServerFindLocals.go popt file line column in
    let print pos = Printf.printf "%s\n" (Pos.string_no_file pos) in
    List.iter result print
  | Outline ->
    let file = cat (Relative_path.to_absolute filename) in
    let results = FileOutline.outline popt file in
    FileOutline.print ~short_pos:true results
  | Find_refs (line, column) ->
    Typing_deps.update_files files_info;
    let genv = ServerEnvBuild.default_genv in
    let env = {(ServerEnvBuild.make_env genv.ServerEnv.config) with
      ServerEnv.files_info;
      ServerEnv.tcopt = opts;
    } in
    let file = cat (Relative_path.to_absolute filename) in
    let include_defs = false in
    let results = ServerFindRefs.go_from_file
      (file, line, column, include_defs) genv env in
    ClientFindRefs.print_ide_readable results;
  | Highlight_refs (line, column) ->
    let file = cat (Relative_path.to_absolute filename) in
    let results = ServerHighlightRefs.go (file, line, column) opts  in
    ClientHighlightRefs.go results ~output_json:false;
  | Suggest
  | Infer_return_types
  | Errors ->
      let errors = check_errors opts errors files_info in
      if mode = Suggest
      then Relative_path.Map.iter files_info (suggest_and_print opts);
      if mode = Infer_return_types
      then Relative_path.Map.iter files_info (infer_return opts);
      if errors <> []
      then (error (List.hd_exn errors); exit 2)
      else Printf.printf "No errors\n"
  | AllErrors ->
      let errors = check_errors opts errors files_info in
      if errors <> []
      then (List.iter ~f:(error ~indent:true) errors; exit 2)
      else Printf.printf "No errors\n"
  | Decl_compare ->
    test_decl_compare filename popt files_contents opts files_info

(*****************************************************************************)
(* Main entry point *)
(*****************************************************************************)

let decl_and_run_mode {filename; mode; no_builtins; tcopt} popt =
  if mode = Dump_deps then Typing_deps.debug_trace := true;
  Local_id.track_names := true;
  Ident.track_names := true;
  let builtins = if no_builtins then "" else builtins in
  let filename = Relative_path.create Relative_path.Dummy filename in
  let files_contents = file_to_files filename in
  let files_contents_with_builtins = Relative_path.Map.add files_contents
    ~key:builtins_filename ~data:builtins in

  let errors, files_info, _ =
    parse_name_and_decl popt files_contents_with_builtins tcopt in

  handle_mode mode filename tcopt popt files_contents files_info
    (Errors.get_error_list errors)

let main_hack ({filename; mode; no_builtins; _} as opts) =
  (* TODO: We should have a per file config *)
  let popt = ParserOptions.default in
  Sys_utils.signal Sys.sigusr1
    (Sys.Signal_handle Typing.debug_print_last_pos);
  EventLogger.init EventLogger.Event_logger_fake 0.0;
  let _handle = SharedMem.init GlobalConfig.default_sharedmem_config in
  let tmp_hhi = Path.concat (Path.make Sys_utils.temp_dir_name) "hhi" in
  Hhi.set_hhi_root_for_unit_test tmp_hhi;
  match mode with
  | Ai ai_options ->
    Ai.do_ Typing_check_utils.check_defs filename ai_options
  | _ ->
    decl_and_run_mode opts popt

(* command line driver *)
let _ =
  if ! Sys.interactive
  then ()
  else
    (* On windows, setting 'binary mode' avoids to output CRLF on
       stdout.  The 'text mode' would not hurt the user in general, but
       it breaks the testsuite where the output is compared to the
       expected one (i.e. in given file without CRLF). *)
    set_binary_mode_out stdout true;
    let options = parse_options () in
    Unix.handle_unix_error main_hack options
