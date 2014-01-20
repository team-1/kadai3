kadai3
======

スライス機能付きルーティングスイッチ (仮想ネットワーク)

API について
------

スライス機能付きスイッチ操作用 API については、以下の wiki ページを参照して下さい。

[REST API 一覧](https://github.com/team-1/kadai3/wiki/REST-API-一覧)


使用法
------

おなじみ `trema run` で実行すると、スライス機能付きルーティングスイッチとして動きます。
スライスに関する情報は、データベース SQLite3 で管理しています。
併せて、ルーティングのために収集したトポロジ情報がテキスト/グラフで見えます。

スイッチ 3 台の三角形トポロジ:

```shell
$ trema run ./sliceable-switch.rb -c triangle.conf
```

スイッチ 10 台のフルメッシュ:

```shell
$ trema run ./sliceable-switch.rb -c fullmesh.conf
```

スイッチやポートを落としたり上げたり、
ホスト間でパケットを送受信してトポロジの変化を楽しむ:
(以下、別ターミナルで)

```shell
$ trema kill 0x1  # スイッチ 0x1 を落とす
$ trema up 0x1  # 落としたスイッチ 0x1 をふたたび起動
$ trema port_down --switch 0x1 --port 1  # スイッチ 0x1 のポート 1 を落とす
$ trema port_up --switch 0x1 --port 1  # 落としたポートを上げる
$ trema send_packet --source host1 --dest host2 # ホスト host1 から host2 へパケットを送信する
```

graphviz でトポロジ画像を出す:

```shell
$ trema run "./sliceable-switch.rb graphviz /tmp/topology.png" -c fullmesh.conf
```

graphviz でトポロジ画像 (ポート番号付) を出す:

- '-p' オプションを使う

```shell
$ trema run "./sliceable-switch.rb -p graphviz /tmp/topology.png" -c fullmesh.conf
```

LLDP の宛先 MAC アドレスを任意のやつに変える:

```shell
$ trema run "./sliceable-switch.rb --destination_mac 11:22:33:44:55:66" -c fullmesh.conf
```

スライス機能付きスイッチを終了する:

```shell
$ trema killall
```