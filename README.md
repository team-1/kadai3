kadai2
======

ルーティングスイッチ

使用法
------

おなじみ `trema run` で実行すると、ルーティングスイッチとして動きます。
併せて、ルーティングのために収集したトポロジ情報がテキスト/グラフで見えます。

スイッチ 3 台の三角形トポロジ:

```shell
$ trema run ./routing-switch.rb -c triangle.conf
```

スイッチ 10 台のフルメッシュ:

```shell
$ trema run ./routing-switch.rb -c fullmesh.conf
```

スイッチやポートを落としたり上げたりしてトポロジの変化を楽しむ:
(以下、別ターミナルで)

```shell
$ trema kill 0x1  # スイッチ 0x1 を落とす
$ trema up 0x1  # 落としたスイッチ 0x1 をふたたび起動
$ trema port_down --switch 0x1 --port 1  # スイッチ 0x1 のポート 1 を落とす
$ trema port_up --switch 0x1 --port 1  # 落としたポートを上げる
```

graphviz でトポロジ画像を出す:

```shell
$ trema run "./routing-switch.rb graphviz /tmp/topology.png" -c fullmesh.conf
```

graphviz でトポロジ画像 (ポート番号付) を出す:

- '-p' オプションを使う

```shell
$ trema run "./routing-switch.rb -p graphviz /tmp/topology.png" -c fullmesh.conf
```

LLDP の宛先 MAC アドレスを任意のやつに変える:

```shell
$ trema run "./routing-switch.rb --destination_mac 11:22:33:44:55:66" -c fullmesh.conf
```
