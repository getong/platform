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

-module(barrel_dbs_sup).
-author("Benoit Chesneau").

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-define(SERVER, ?MODULE).

-export([start_db/2, stop_db/1, await_db/1]).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() ->
  supervisor:start_link({local, ?SERVER}, ?MODULE, []).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

-spec init(any()) ->
  {ok, {supervisor:sup_flags(), [supervisor:child_spec()]}}.
init([]) ->
  {ok, {{one_for_one, 5, 10}, []}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private

-spec start_db(term(), atom()) -> supervisor:startchild_ret().
start_db(Name, Store) ->
  Spec = #{
    id => Name,
    start => {barrel_db_sup, start_link, [Name, Store]},
    restart => permanent,
    shutdown => 5000,
    type => supervisor,
    modules => [barrel_db_sup]
  },
  supervisor:start_child(?MODULE, Spec).

-spec stop_db(term()) -> ok |{error, term()}.
stop_db(Name) ->
  case supervisor:terminate_child(?MODULE, Name) of
    ok ->
      _ = supervisor:delete_child(?MODULE, Name),
      ok;
    {error, not_found} -> ok;
    Error ->
      Error
  end.

await_db(Name) ->
  _ = gproc:await({n, l, {db_sup, Name}}, 5000),
  ok.
