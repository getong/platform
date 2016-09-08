%% Copyright 2016, Benoit Chesneau
%%
%% Licensed under the Apache License, Version 2.0 (the "License"); you may not
%% use this file except in compliance with the License. You may obtain a copy of
%% the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
%% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
%% License for the specific language governing permissions and limitations under
%% the License.

%% Created by benoitc on 03/09/16.

-module(barrel_store).
-author("Benoit Chesneau").
-behaviour(gen_server).

%% API
-export([
  open_db/2,
  clean_db/3,
  all_dbs/1,
  get_doc_info/3,
  write_doc/6,
  get_doc/7,
  fold_by_id/5,
  changes_since/5
]).

-export([start_link/3]).

%% gen_server callbacks
-export([
  init/1,
  handle_call/3,
  handle_cast/2,
  handle_info/2,
  terminate/2,
  code_change/3
]).

-define(DEFAULT_WORKERS, 100).

-record(state, {
  mod :: atom(),
  mod_state :: any()
}).

%%%===================================================================
%%% Types
%%%===================================================================

-type state() :: #state{}.

%%%=============================================================================
%%% Callbacks
%%%=============================================================================

-callback init(atom(), term()) -> {ok, any()}.

-callback open_db(term(), term()) -> term().

-callback clean_db(term(), term(), term()) -> ok | {error, term()}.

-callback all_dbs(term()) -> list().

-callback get_doc_info(term(), binary(), binary()) -> {ok, map()} | {error, term()}.

-callback write_doc(term(), binary(), binary(), integer(), map(), map())
    -> {ok, integer()} | {error, term()}.

-callback get_doc(DbId :: binary(), DocId :: binary(), Rev :: barrel_db:rev(),
  History :: boolean(), MaxHistory::integer(), HistoryForm::list(), State :: any())
    -> {ok, Body :: map() } | {error, term()}.


-callback fold_by_id(DbId :: binary(), Fun :: fun(),
                     AccIn::any(), FoldOpts :: list(), State::any()) -> AccOut :: any().

-callback changes_since(DbId :: binary(), Since :: integer(), Fun :: fun(),
                        AccIn::any(), State::any()) -> AccOut :: any().

%%%===================================================================
%%% API
%%%===================================================================

open_db(Store, Name) ->
  wpool:call(Store, {open_db, Name}).

clean_db(Store, Name, DbId) ->
  wpool:call(Store, {clean_db, Name, DbId}).

all_dbs(Store) ->
  wpool:call(Store, all_dbs).

get_doc_info(Store, DbId, DocId) ->
  wpool:call(Store, {get_doc_info, DbId, DocId}).

write_doc(Store, DbId, DocId, LastSeq, DocInfo, Body) ->
  wpool:call(Store, {write_doc, DbId, DocId, LastSeq, DocInfo, Body}).

get_doc(Store, DbId, DocId, Rev, WithHistory, MaxHistory, HistoryFrom) ->
  wpool:call(Store, {get_doc, DbId, DocId, Rev, WithHistory, MaxHistory, HistoryFrom}).


fold_by_id(Store, DbId, Fun, AccIn, Opts) ->
  wpool:call(Store, {fold_by_id, DbId, Fun, AccIn, Opts}).

changes_since(Store, DbId, Since, Fun, AccIn) ->
  wpool:call(Store, {changes_since, DbId, Since, Fun, AccIn}).


%% @doc Starts and links a new process for the given store implementation.
-spec start_link(atom(), module(), [term()]) -> {ok, pid()}.
start_link(Name, Module, Options) ->
  PoolSize = proplists:get_value(workers, Options, ?DEFAULT_WORKERS),
  _ = code:ensure_loaded(Module),
  case erlang:function_exported(Module, pre_start, 2) of
    false ->
      lager:info("function pre_start not exported", []),
      ok;
    true -> Module:pre_start(Name, Options)
  end,
  
  WPoolConfigOpts = application:get_env(barrel, wpool_opts, []),
  WPoolOptions = [
    {overrun_warning, 5000},
    {overrun_handler, {barrel_lib, report_overrun}},
    {workers, PoolSize},
    {worker, {?MODULE, [Name, Module, Options]}}
  ],
  wpool:start_pool(Name, WPoolConfigOpts ++ WPoolOptions).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================
%%%
-spec init(term()) -> {ok, state()}.
init([Name, Mod, Opts]) ->
  {ok, ModState} = Mod:init(Name, Opts),
  {ok, #state{mod=Mod, mod_state=ModState}}.

-spec handle_call(term(), term(), state()) -> {reply, term(), state()}.
handle_call({open_db, Name}, _From, State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:open_db(ModState, Name),
  {reply, Reply, State};

handle_call({clean_db, Name, DbId}, _From, State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:clean_db(Name, DbId, ModState),
  {reply, Reply, State};

handle_call({get_doc_info, DbId, DocId}, _From, State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:get_doc_info(DbId, DocId, ModState),
  {reply, Reply, State};

handle_call({write_doc, DbId, DocId, LastSeq, DocInfo, Body}, _From, State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:write_doc(DbId, DocId, LastSeq, DocInfo, Body, ModState),
  {reply, Reply, State};

handle_call({get_doc, DbId, DocId, Rev, WithHistory, MaxHistory, HistoryFrom}, _From,  State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:get_doc(DbId, DocId, Rev, WithHistory, MaxHistory, HistoryFrom, ModState),
  {reply, Reply, State};

handle_call({fold_by_id, DbId, Fun, AccIn, Opts}, _From,  State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:fold_by_id(DbId, Fun, AccIn, Opts, ModState),
  {reply, Reply, State};

handle_call({changes_since, DbId, Since, Fun, AccIn}, _From,  State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:changes_since(DbId, Since, Fun, AccIn, ModState),
  {reply, Reply, State};

handle_call(all_dbs, _From, State=#state{ mod=Mod, mod_state=ModState}) ->
  Reply = Mod:all_dbs(ModState),
  {reply, Reply, State};


handle_call(_Request, _From, State) ->
  io:format("request is ~p~nstate is ~p~n", [_Request, State]),
  {reply, bad_call, State}.

-spec handle_cast(term(), state()) -> {noreply, state()}.
handle_cast(_Msg, State) ->
  {noreply, State}.

-spec handle_info(term(), state()) -> {noreply, state()}.
handle_info(_Info, State) ->
  {noreply, State}.

-spec terminate(term(), state()) -> ok.
terminate(_Reason, _State) ->
  ok.

-spec code_change(term(), state(), term()) -> {ok, state()}.
code_change(_OldVsn, State, _Extra) ->
  {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

