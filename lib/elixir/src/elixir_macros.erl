%% Those macros behave like they belong to Kernel,
%% but do not since they need to be implemented in Erlang.
-module(elixir_macros).
-export([translate/2]).
-import(elixir_translator, [translate_each/2, translate_args/2, translate_apply/7]).
-import(elixir_scope, [umergec/2]).
-import(elixir_errors, [syntax_error/3, syntax_error/4,
  assert_no_function_scope/3, assert_module_scope/3, assert_no_assign_or_guard_scope/3]).
-include("elixir.hrl").

-define(FUNS(Kind), Kind == def; Kind == defp; Kind == defmacro; Kind == defmacrop).
-define(IN_TYPES(Kind), Kind == atom orelse Kind == integer orelse Kind == float).

-compile({parse_transform, elixir_transform}).

%% Operators

translate({ '+', _Meta, [Expr] }, S) when is_number(Expr) ->
  translate_each(Expr, S);

translate({ '-', _Meta, [Expr] }, S) when is_number(Expr) ->
  translate_each(-1 * Expr, S);

translate({ Op, Meta, Exprs }, S) when is_list(Exprs),
    Op == '<-' orelse Op == '--' ->
  assert_no_assign_or_guard_scope(Meta, Op, S),
  translate_each({ '__op__', Meta, [Op|Exprs] }, S);

translate({ Op, Meta, Exprs }, S) when is_list(Exprs),
    Op == '+'   orelse Op == '-'   orelse Op == '*'   orelse Op == '/' orelse
    Op == '++'  orelse Op == 'not' orelse Op == 'and' orelse Op == 'or' orelse
    Op == 'xor' orelse Op == '<'   orelse Op == '>'   orelse Op == '<=' orelse
    Op == '>='  orelse Op == '=='  orelse Op == '!='  orelse Op == '===' orelse
    Op == '!==' ->
  translate_each({ '__op__', Meta, [Op|Exprs] }, S);

translate({ '!', Meta, [{ '!', _, [Expr] }] }, S) ->
  { TExpr, SE } = translate_each(Expr, S),
  elixir_tree_helpers:convert_to_boolean(?line(Meta), TExpr, true, S#elixir_scope.context == guard, SE);

translate({ '!', Meta, [Expr] }, S) ->
  { TExpr, SE } = translate_each(Expr, S),
  elixir_tree_helpers:convert_to_boolean(?line(Meta), TExpr, false, S#elixir_scope.context == guard, SE);

translate({ in, Meta, [Left, Right] }, #elixir_scope{extra_guards=nil} = S) ->
  { _, TExpr, TS } = translate_in(Meta, Left, Right, S),
  { TExpr, TS };

translate({ in, Meta, [Left, Right] }, #elixir_scope{extra_guards=Extra} = S) ->
  { TVar, TExpr, TS } = translate_in(Meta, Left, Right, S),
  { TVar, TS#elixir_scope{extra_guards=[TExpr|Extra]} };

%% Functions

translate({ function, Meta, [[{do,{ '->',_,Pairs}}]] }, S) ->
  assert_no_assign_or_guard_scope(Meta, 'function', S),
  elixir_translator:translate_fn(Meta, Pairs, S);

translate({ function, Meta, [{ '/', _, [{{ '.', _ ,[M, F] }, _ , [] }, A]}] }, S) ->
  translate({ function, Meta, [M, F, A] }, S);

translate({ function, Meta, [{ '/', _, [{F, _, Q}, A]}] }, S) when is_atom(Q) ->
  translate({ function, Meta, [F, A] }, S);

translate({ function, Meta, [_] }, S) ->
  assert_no_assign_or_guard_scope(Meta, 'function', S),
  syntax_error(Meta, S#elixir_scope.file, "invalid args for function");

translate({ function, Meta, [_, _] = Args }, S) ->
  assert_no_assign_or_guard_scope(Meta, 'function', S),

  case translate_args(Args, S) of
    { [{atom,_,Name}, {integer,_,Arity}], SA } ->
      case elixir_dispatch:import_function(Meta, Name, Arity, SA) of
        false -> syntax_error(Meta, S#elixir_scope.file, "cannot convert a macro to a function");
        Else  -> Else
      end;
    _ ->
      syntax_error(Meta, S#elixir_scope.file, "cannot dynamically retrieve local function. use function(module, fun, arity) instead")
  end;

translate({ function, Meta, [_,_,_] = Args }, S) when is_list(Args) ->
  assert_no_assign_or_guard_scope(Meta, 'function', S),
  { [A,B,C], SA } = translate_args(Args, S),
  { { 'fun', ?line(Meta), { function, A, B, C } }, SA };

%% @

translate({'@', Meta, [{ Name, _, [Arg] }]}, S) when Name == typep; Name == type; Name == spec; Name == callback; Name == opaque ->
  case elixir_compiler:get_opt(internal) of
    true  -> { { nil, ?line(Meta) }, S };
    false ->
      Call = { { '.', Meta, ['Elixir.Kernel.Typespec', spec_to_macro(Name)] }, Meta, [Arg] },
      translate_each(Call, S)
  end;

translate({'@', Meta, [{ Name, _, Args }]}, S) ->
  assert_module_scope(Meta, '@', S),

  case is_reserved_data(Name) andalso elixir_compiler:get_opt(internal) of
    true ->
      { { nil, ?line(Meta) }, S };
    _ ->
      case Args of
        [Arg] ->
          case S#elixir_scope.function of
            nil ->
              translate_each({
                { '.', Meta, ['Elixir.Module', put_attribute] },
                  Meta,
                  [ { '__MODULE__', Meta, false }, Name, Arg ]
              }, S);
            _  ->
              syntax_error(Meta, S#elixir_scope.file,
                "cannot dynamically set attribute @~s inside a function", [Name])
          end;
        _ when is_atom(Args) or (Args == []) ->
          case S#elixir_scope.function of
            nil ->
              translate_each({
                { '.', Meta, ['Elixir.Module', get_attribute] },
                Meta,
                [ { '__MODULE__', Meta, false }, Name ]
              }, S);
            _ ->
              Contents = 'Elixir.Module':get_attribute(S#elixir_scope.module, Name),
              { elixir_tree_helpers:abstract_syntax(Contents), S }
          end;
        _ ->
          syntax_error(Meta, S#elixir_scope.file, "expected 0 or 1 argument for @~s, got: ~p", [Name, length(Args)])
      end
  end;

%% Case

translate({'case', Meta, [Expr, KV]}, S) ->
  assert_no_assign_or_guard_scope(Meta, 'case', S),
  Clauses = elixir_clauses:get_pairs(Meta, do, KV, S),
  { TExpr, NS } = translate_each(Expr, S),

  RClauses = case elixir_tree_helpers:returns_boolean(TExpr) of
    true  -> rewrite_case_clauses(Clauses);
    false -> Clauses
  end,

  { TClauses, TS } = elixir_clauses:match(Meta, RClauses, NS),
  { { 'case', ?line(Meta), TExpr, TClauses }, TS };

%% Try

translate({'try', Meta, [Clauses]}, RawS) ->
  S = RawS#elixir_scope{noname=true},
  assert_no_assign_or_guard_scope(Meta, 'try', S),

  Do = proplists:get_value('do', Clauses, nil),
  { TDo, SB } = elixir_translator:translate_each(Do, S),

  Catch = [Tuple || { X, _ } = Tuple <- Clauses, X == 'rescue' orelse X == 'catch'],
  { TCatch, SC } = elixir_try:clauses(Meta, Catch, umergec(S, SB)),

  After = proplists:get_value('after', Clauses, nil),
  { TAfter, SA } = elixir_translator:translate_each(After, umergec(S, SC)),

  Else = elixir_clauses:get_pairs(Meta, else, Clauses, S),
  { TElse, SE } = elixir_clauses:match(Meta, Else, umergec(S, SA)),

  { { 'try', ?line(Meta), pack(TDo), TElse, TCatch, pack(TAfter) }, umergec(RawS, SE) };

%% Receive

translate({'receive', Meta, [KV] }, S) ->
  assert_no_assign_or_guard_scope(Meta, 'receive', S),
  Do = elixir_clauses:get_pairs(Meta, do, KV, S, true),

  case lists:keyfind('after', 1, KV) of
    false ->
      { TClauses, SC } = elixir_clauses:match(Meta, Do, S),
      { { 'receive', ?line(Meta), TClauses }, SC };
    _ ->
      After = elixir_clauses:get_pairs(Meta, 'after', KV, S),
      { TClauses, SC } = elixir_clauses:match(Meta, Do ++ After, S),
      { FClauses, TAfter } = elixir_tree_helpers:split_last(TClauses),
      { _, _, [FExpr], _, FAfter } = TAfter,
      { { 'receive', ?line(Meta), FClauses, FExpr, FAfter }, SC }
  end;

%% Definitions

translate({defmodule, Meta, [Ref, KV]}, S) ->
  { TRef, _ } = translate_each(Ref, S),

  Block = case lists:keyfind(do, 1, KV) of
    { do, DoValue } -> DoValue;
    false -> syntax_error(Meta, S#elixir_scope.file, "expected do: argument in defmodule")
  end,

  { FRef, FS } = case TRef of
    { atom, _, Module } ->
      FullModule = module_ref(Ref, Module, S#elixir_scope.module),

      RS = case elixir_aliases:nesting(S#elixir_scope.module, FullModule) of
        false -> S;
        Alias -> element(2, translate_each({ alias, Meta, [FullModule, [{ as, Alias }]] }, S))
      end,

      {
        { atom, Meta, FullModule },
        RS#elixir_scope{scheduled=[FullModule|S#elixir_scope.scheduled]}
      };
    _ ->
      { TRef, S }
  end,

  { elixir_module:translate(Meta, FRef, Block, S#elixir_scope{check_clauses=true}), FS };

translate({Kind, Meta, [Call]}, S) when ?FUNS(Kind) ->
  translate({Kind, Meta, [Call, nil]}, S);

translate({Kind, Meta, [Call, Expr]}, S) when ?FUNS(Kind) ->
  assert_module_scope(Meta, Kind, S),
  assert_no_function_scope(Meta, Kind, S),

  { TCall, Guards } = elixir_clauses:extract_guards(Call),
  { Name, Args }    = case elixir_clauses:extract_args(TCall) of
    error -> syntax_error(Meta, S#elixir_scope.file,
               "invalid syntax in ~s ~s", [Kind, 'Elixir.Macro':to_binary(TCall)]);
    Tuple -> Tuple
  end,

  assert_no_aliases_name(Meta, Name, Args, S),

  TName   = elixir_tree_helpers:abstract_syntax(Name),
  TArgs   = elixir_tree_helpers:abstract_syntax(Args),
  TGuards = elixir_tree_helpers:abstract_syntax(Guards),
  TExpr   = elixir_tree_helpers:abstract_syntax(Expr),

  { elixir_def:wrap_definition(Kind, Meta, TName, TArgs, TGuards, TExpr, S), S };

translate({Kind, Meta, [Name, Args, Guards, Expr]}, S) when ?FUNS(Kind) ->
  assert_module_scope(Meta, Kind, S),
  assert_no_function_scope(Meta, Kind, S),
  { TName, NS }   = translate_each(Name, S),
  { TArgs, AS }   = translate_each(Args, NS),
  { TGuards, GS } = translate_each(Guards, AS),
  { TExpr, ES }   = translate_each(Expr, GS),
  { elixir_def:wrap_definition(Kind, Meta, TName, TArgs, TGuards, TExpr, ES), ES };

%% Apply - Optimize apply by checking what doesn't need to be dispatched dynamically

translate({ apply, Meta, [Left, Right, Args] }, S) when is_list(Args) ->
  { TLeft,  SL } = translate_each(Left, S),
  { TRight, SR } = translate_each(Right, umergec(S, SL)),
  translate_apply(Meta, TLeft, TRight, Args, S, SL, SR);

translate({ apply, Meta, Args }, S) ->
  { TArgs, NS } = translate_args(Args, S),
  { ?wrap_call(?line(Meta), erlang, apply, TArgs), NS }.

%% Helpers

translate_in(Meta, Left, Right, S) ->
  Line = ?line(Meta),

  { TLeft, SL } = case Left of
    { '_', _, Atom } when is_atom(Atom) ->
      elixir_scope:build_erl_var(Line, S);
    _ ->
      translate_each(Left, S)
  end,

  { TRight, SR } = translate_each(Right, SL),

  Cache = (S#elixir_scope.context == nil),

  { Var, SV } = case Cache of
    true  -> elixir_scope:build_erl_var(Line, SR);
    false -> { TLeft, SR }
  end,

  Expr = case TRight of
    { cons, _, _, _ } ->
      [H|T] = elixir_tree_helpers:cons_to_list(TRight),
      lists:foldr(fun(X, Acc) ->
        { op, Line, 'orelse', { op, Line, '==', Var, X }, Acc }
      end, { op, Line, '==', Var, H }, T);
    { string, _, [H|T] } ->
      lists:foldl(fun(X, Acc) ->
        { op, Line, 'orelse', { op, Line, '==', Var, { integer, Line, X } }, Acc }
      end, { op, Line, '==', Var, { integer, Line, H } }, T);
    { tuple, _, [{ atom, _, 'Elixir.Range' }, Start, End] } ->
      case { Start, End } of
        { { K1, _, StartInt }, { K2, _, EndInt } } when ?IN_TYPES(K1), ?IN_TYPES(K2), StartInt =< EndInt ->
          increasing_compare(Line, Var, Start, End);
        { { K1, _, _ }, { K2, _, _ } } when ?IN_TYPES(K1), ?IN_TYPES(K2) ->
          decreasing_compare(Line, Var, Start, End);
        _ ->
          { op, Line, 'orelse',
            { op, Line, 'andalso',
              { op, Line, '=<', Start, End},
              increasing_compare(Line, Var, Start, End) },
            { op, Line, 'andalso',
              { op, Line, '<', End, Start},
              decreasing_compare(Line, Var, Start, End) } }
      end;
    _ ->
      syntax_error(Meta, S#elixir_scope.file, "invalid args for operator in, it expects an explicit array or an explicit range on the right side")
  end,

  case Cache of
    true  -> { Var, { block, Line, [ { match, Line, Var, TLeft }, Expr ] }, SV };
    false -> { Var, Expr, SV }
  end.

increasing_compare(Line, Var, Start, End) ->
  { op, Line, 'andalso',
    { op, Line, '>=', Var, Start },
    { op, Line, '=<', Var, End } }.

decreasing_compare(Line, Var, Start, End) ->
  { op, Line, 'andalso',
    { op, Line, '=<', Var, Start },
    { op, Line, '>=', Var, End } }.

rewrite_case_clauses([{do,[{in,_,[{'_',_,_},[false,nil]]}],False},{do,[{'_',_,_}],True}]) ->
  [{do,[false],False},{do,[true],True}];

rewrite_case_clauses(Clauses) ->
  Clauses.

module_ref(Raw, Module, Nesting) when is_atom(Raw); Nesting == nil ->
  Module;

module_ref({ '__aliases__', _, ['Elixir'|_] }, Module, _Nesting) ->
  Module;

module_ref(_Raw, Module, Nesting) ->
  elixir_aliases:concat([Nesting, Module]).

is_reserved_data(moduledoc) -> true;
is_reserved_data(doc)       -> true;
is_reserved_data(_)         -> false.

spec_to_macro(type)     -> deftype;
spec_to_macro(typep)    -> deftypep;
spec_to_macro(opaque)   -> defopaque;
spec_to_macro(spec)     -> defspec;
spec_to_macro(callback) -> defcallback.

% Pack a list of expressions from a block.
pack({ 'block', _, Exprs }) -> Exprs;
pack(Expr)                  -> [Expr].

assert_no_aliases_name(Meta, '__aliases__', [Atom], #elixir_scope{file=File}) when is_atom(Atom) ->
  Message = "function names should start with lowercase characters or underscore, invalid name ~s",
  syntax_error(Meta, File, Message, [atom_to_binary(Atom, utf8)]);

assert_no_aliases_name(_Meta, _Aliases, _Args, _S) ->
  ok.