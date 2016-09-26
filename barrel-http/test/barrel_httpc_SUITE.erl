%% Copyright 2016, Bernard Notarianni
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

-module(barrel_httpc_SUITE).

-export([ all/0
        , end_per_suite/1
        , end_per_testcase/2
        , init_per_suite/1
        , init_per_testcase/2
        ]).

-export([ info_database/1
        , create_doc/1
        , put_get_delete/1
        , changes_since/1
        , db_updated/1
        ]).

all() -> [ info_database
         , create_doc
         , put_get_delete
         , changes_since
         , db_updated
         ].

init_per_suite(Config) ->
  {ok, _} = application:ensure_all_started(barrel),
  Config.

init_per_testcase(_, Config) ->
  ok = barrel_db:start(<<"testdb">>, barrel_test_rocksdb),
  {ok, _} = barrel_httpc:start_link(),
  ok = barrel_httpc:start(url(), undefined),
  Config.

end_per_testcase(_, Config) ->
  stopped = barrel_httpc:stop(),
  ok = barrel_db:clean(<<"testdb">>),
  Config.

end_per_suite(Config) ->
  catch erocksdb:destroy(<<"testdb">>),
  Config.

%% ----------

url() ->
  {barrel_httpc, <<"http://localhost:8080/testdb">>}.

info_database(_Config) ->
  {ok, Info} = barrel_httpc:infos(url()),
  <<"testdb">> = maps:get(<<"name">>, Info),
  ok.

create_doc(_Config) ->
  Doc = #{<<"v">> => 1},
  {ok, DocId, RevId} =  barrel_httpc:post(url(), Doc, []),
  CreatedDoc = Doc#{ <<"_id">> => DocId, <<"_rev">> => RevId},
  {ok, CreatedDoc} = barrel_httpc:get(url(), DocId, []),
  {error, not_found} =  barrel_httpc:post(url(), CreatedDoc, []),
  Doc2 = #{<<"_id">> => <<"b">>, <<"v">> => 1},
  {ok, <<"b">>, _RevId2} =  barrel_httpc:post(url(), Doc2, []).


put_get_delete(_Config) ->
  {error, not_found} = barrel_httpc:get(url(), <<"a">>, []),
  Doc = #{ <<"_id">> => <<"a">>, <<"v">> => 1},
  {ok, <<"a">>, RevId} = barrel_httpc:put(url(), <<"a">>, Doc, []),
  Doc2 = Doc#{<<"_rev">> => RevId},
  {ok, Doc2} = barrel_httpc:get(url(), <<"a">>, []),
  {ok, <<"a">>, _RevId2} = barrel_httpc:delete(url(), <<"a">>, RevId, []),
  {ok, DeletedDoc} = barrel_httpc:get(url(), <<"a">>, []),
  true = maps:get(<<"_deleted">>, DeletedDoc).

changes_since(_Config) ->
  Doc = #{ <<"_id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel_httpc:put(url(), <<"aa">>, Doc, []),
  Doc2 = #{ <<"_id">> => <<"bb">>, <<"v">> => 1},
  {ok, <<"bb">>, _RevId2} = barrel_httpc:put(url(), <<"bb">>, Doc2, []),

  [{2, <<"bb">>}, {1, <<"aa">>}] = since(0),
                 [{2, <<"bb">>}] = since(1),
                              [] = since(2),

  {ok, <<"cc">>, _RevId2} = barrel_httpc:put(url(), <<"cc">>, Doc2, []),

                 [{3, <<"cc">>}] = since(2).

db_updated(_Config) ->

  ok = barrel_event:reg(url()),
  Doc = #{ <<"_id">> => <<"aa">>, <<"v">> => 1},
  {ok, <<"aa">>, _RevId} = barrel_httpc:put(url(), <<"aa">>, Doc, []),
  
  Msg = one_msg(),
  DbRef = url(),
  {'$barrel_event', DbRef, db_updated} = Msg,
  true = queue_is_empty(),
 
  Doc2 = #{ <<"_id">> => <<"bb">>, <<"v">> => 1},
  {ok, <<"bb">>, _RevId2} = barrel_httpc:put(url(), <<"bb">>, Doc2, []),
                        
  Msg = one_msg(),
  DbRef = url(),
  {'$barrel_event', DbRef, db_updated} = Msg,
  true = queue_is_empty(),

  ok = barrel_event:unreg(),
  ok.


since(Since) ->
  Fun = fun(Seq, DocInfo, Doc, Acc) ->
            {error, doc_not_fetched} = Doc,
            Id = maps:get(id, DocInfo),
            {ok, [{Seq, Id}|Acc]}
        end,
  barrel_httpc:changes_since(url(), Since, Fun, []).
 

one_msg() -> 
  receive
    M -> M
  after 2000 ->
      {error, timeout}
  end.

queue_is_empty() ->
  {message_queue_len, 0} = erlang:process_info(self(), message_queue_len),
  true.
