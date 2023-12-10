# CloudFlare Workersを使ってR2にアクセスする

<a href="https://qiita.com/advent-calendar/2023/yumemi-23-graduation">
  <img alt="YUMEMI New Grad Advent Calendar 2023" width="1240" height="112" src="https://qiita-image-store.s3.ap-northeast-1.amazonaws.com/0/672609/6d8a7098-9aef-a19a-54fe-83a2d493e033.png">
</a>

[前回の記事](https://qiita.com/k-kojima-yumemi/private/1567716b2a67b45d7229)ではGradleを使ってR2にファイルを保存しました。
またPublicに公開する設定をしました。

しかしR2の公開設定だけではリポジトリを利用する人に利用可能なパッケージの一覧を見せることができません。
maven-metadata.xmlの参照はできるのでバージョンはわかりますが、ブラウザからアクセスするとファイルがダウンロードされてしまい気軽に確認できません。
(GradleからアップロードするとContent-Typeが `application/octet-stream` になるため)

そこで今回はWorkersに簡単なアプリケーションを作成し、一覧として見られるようにしていきます。
またファイルの配布もできるようにしてWorkersのURLとMaven RepositoryのURLを一致させられるようにすることを目指します。
R2のBucketと同じアカウントにWorkersを作成します。

基本的にはドキュメントに沿ってコードを書くだけの記事です。
Workersの作成とドメインの設定はTerraformで行います。
Workersの設定とコードのアップロードはWranglerで行います。

コードは以下のリポジトリで公開しています。

https://github.com/k-kojima-yumemi/fluffy-tribble/tree/main

# 参考

* Workers用のコードを作成
  * https://developers.cloudflare.com/r2/api/workers/workers-api-usage/
  * https://developers.cloudflare.com/workers/tutorials/configure-your-cdn/
  * https://developers.cloudflare.com/r2/api/workers/workers-api-reference/
  * https://hono.dev/getting-started/cloudflare-workers#bindings
* Workersの設定
  * https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs
  * https://developers.cloudflare.com/workers/configuration/
  * https://developers.cloudflare.com/workers/configuration/routing/
  * https://blog.cloudflare.com/deploy-workers-using-terraform/
    * 内容が古いです

# Workers用のコードを作成

[Hono](https://hono.dev/)を使っていきます。

https://hono.dev/getting-started/cloudflare-workers

HonoのTutorialの中にR2を扱う方法が書かれているのでこちらも参考にしていきます。

https://hono.dev/getting-started/cloudflare-workers#bindings

## R2のBucketのBindingの設定

まず、R2のBucketのBindingの設定をしていきます。この操作によってWorkersのコードからR2へ簡単にアクセスすることができます。
HonoでWorkers用にファイルを生成するとwrangler.tomlが生成されているので、こちらに以下を追記します。
もともとコメントアウトされて同じ内容が書かれています。

```toml
[[r2_buckets]]
binding = "MAVEN_BUCKET"
bucket_name = "koma-maven"
preview_bucket_name = "koma-maven"
```

これでR2の `koma-maven` という名前のBucketに `MAVEN_BUCKET` の変数名でアクセスできるようになります。
`preview_bucket_name` の設定は動作確認をする時に使うBucketの名前です。今回は本番と同じBucketを設定しますが、PUTなどの動作を入れる際に開発用に用意したBucketを使ってください。
Bindingの設定については以下のドキュメントに詳しい説明が書かれています。
地理的な制約がある場合の設定も書かれているので該当する場合にはその設定も必要です。今回は特に設定しません。

https://developers.cloudflare.com/workers/wrangler/configuration/#r2-buckets

## Workersのコードでの使用

先ほどBindingしたR2をWorkersで扱うためのコードの記述をしていきます。
JSXを使うためファイルの拡張子をtsからtsxに変更しています。

```typescript index.tsx
type Bindings = {
    MAVEN_BUCKET: R2Bucket;
};

const app = new Hono<{Bindings: Bindings}>();
```

`Bindings` のタイプで先ほど設定したBindingの名前(r2_bucketsの `binding`)を指定します。
これでHonoのcontextから参照できるようになります。

一覧を表示するために以下のようにコードを記述しました。 `/` にアクセスした際にファイルの一覧を表示するようにしています。

```typescript index.tsx
app.get("/", async (c) => {
    const bucket = c.env.MAVEN_BUCKET;
    const items = await bucket.list();
    return c.html(
        <Page title="Files">
            <ol>
                {items.objects.map((o) => {
                    const name = o.key;
                    const path = `/${name}`;
                    return (
                        <li>
                            <a href={path}>{name}</a>
                        </li>
                    );
                })}
            </ol>
        </Page>
    );
});

const Page: FC<{title: string}> = (props) => {
    return html`<!doctype html>
        <html lang="en">
            <head>
                <title>${props.title}</title>
            </head>
            <body>
                ${props.children}
            </body>
        </html>`;
};
```

`c.env.MAVEN_BUCKET` の記述でR2のBucketにアクセスしています。
利用できる関数については以下に記載があります。今回は一覧を取得したいため `list` を使っています。

https://developers.cloudflare.com/r2/api/workers/workers-api-reference/

このコードで以下のように一覧表示ができます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article2/Custom_file_view.png)
ディレクトリ階層ごとに表示したい場合にはlistの引数にprefixを渡したりパスの解析をする必要があります。
またlistの引数で `delimiter` を指定することで返り値に `delimitedPrefixes`
が含まれ、[次の階層の情報が得られる](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/#r2objects)
ようです。

個々のファイルのパスにアクセスした際にファイルの中身が取得できるように、以下のコードを記述しました。

```typescript
app.get("/:prefix{.+$}", async (c) => {
    const bucket = c.env.MAVEN_BUCKET;
    const {prefix} = c.req.param();
    const bucketObject = await bucket.get(prefix);
    if (bucketObject !== null) {
        c.header("etag", '"' + bucketObject.etag + '"');
        c.header("Content-Type", "application/octet-stream");
        return c.stream(async (stream) => {
            await stream.pipe(bucketObject.body);
        });
    } else {
        return c.notFound();
    }
});
```

`get` でファイルを取得し、存在すればその中身を、存在しなければ404を返すようにしています。
[ドキュメント](https://developers.cloudflare.com/r2/api/workers/workers-api-reference/#r2objectbody-definition)
に記載がありますが、`bucketObject.body` でStreamが得られるのでそれを返すようにしています。
今回はContent-Typeを固定で `application/octet-stream` にしていますが、拡張子やファイルの中身から適切なMIME
typesを取得して設定するとブラウザでファイルの中身が確認しやすくなります。

コードの全体はこちらです。

https://github.com/k-kojima-yumemi/fluffy-tribble/blob/main/workers/src/index.tsx

## Workersの動作確認

書いたコードが実際に動作するか確認していきます。

### ローカル

以下のコマンドでローカル環境に立ち上げることができます。
ただしR2の中身を確認することはできません。空のBucketとして振る舞います。

```bash
npx wrangler dev src/index.tsx
```

上のコマンドで実行している途中に `l` を入力すると実際のWorkers上で起動するモードに変わります。(
下記のリモートと同じ挙動になります)

### リモート

実際にR2を使って動作確認するには以下のコマンドで立ち上げます。

```bash
npx wrangler dev src/index.tsx --remote
```

このコマンドでは実際にWorkersにコードを送って、ローカルのポートとの紐付けを行っているようです。
wrangler.tomlの `preview_bucket_name` のBucketを使用できます。

# Workersの作成

以下のコードでリソースの作成を行いました。Terraformで作成まで行い、管理はWranglerで行うようにしています。
(Terraformで管理しているのは関連するリソースをdestroyしやすくするためです)

```terraform
data "http" "script" {
  url = "https://gist.githubusercontent.com/jRiest/7893cf10c550057ce1ff53f270683e1c/raw/3ac7f45302f4f6274703c564864a684e9097bce2/party_parrot_worker.js"
}

resource "cloudflare_worker_script" "worker" {
  account_id = var.cloudflare_account
  # https://blog.cloudflare.com/deploy-workers-using-terraform/
  content    = data.http.script.response_body
  name       = var.worker_name
  lifecycle {
    ignore_changes = [
      content,
      r2_bucket_binding,
    ]
  }
}

resource "cloudflare_worker_domain" "worker_domain" {
  account_id = var.cloudflare_account
  hostname   = "test.${var.bucket_name}.${var.domain}" # test.koma-maven.example.com
  service    = cloudflare_worker_script.worker.name
  zone_id    = data.cloudflare_zone.zone.id
}
```

cloudflare_worker_scriptは初回から有効なコードを指定する必要があるため、[Terraformの例](https://blog.cloudflare.com/deploy-workers-using-terraform/)
に載っていたコードのURLを最初のコードとして使うようにしています。
cloudflare_worker_domainでWorkersを紐づけるドメインを指定しています。CloudFlareでDNSの設定がされているドメインのみが使用できます。
Custom Domainを使うかRouteを使うかは[こちら](https://developers.cloudflare.com/workers/configuration/routing/)
を参照してください。今回はR2にアクセスするだけなのでCustom Domainにしています。
ドメインを持っていない場合はRouteにして、`workers.dev` 配下のサブドメインを使うことになります。今回の範囲では動作が変わることはありません。

この後WranglerでコードのデプロイとBindingの設定を行うのでそれに関連する部分はignore_changesにしています。
他にどのような設定をTerraformでできるかはドキュメントに記載があります。

https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs/resources/worker_script

# Workersのデプロイ

以下のコマンドでデプロイします

```bash
wrangler deploy --minify src/index.tsx
```

上記のWorkersの作成の手順でコードをデプロイしたので、Terraformでアップロードしたコードを上書きしていいかと聞かれます。
yをおして許可します。

その後適切に設定されていれば、cloudflare_worker_domainのhostnameで指定したドメインでアクセスできます。
![](https://raw.githubusercontent.com/k-kojima-yumemi/fluffy-tribble/main/article2/Custom_file_view_url.png)
各ファイルのリンクをクリックすればファイルがダウンロードできます。

# Gradleでの設定

前回R2で用意されているBucketの公開設定で作成したURLをRepositoryに設定していました。

```kotlin
repositories {
    maven {
        name = "R2"
        url = uri("https://koma-maven.example.com/")
    }
}

dependencies {
    implementation("jp.co.yumemi.koma:lib:1.1-SNAPSHOT")
}
```

それを今回Workersを配置したURLに変更します。

```diff_kotlin
- url = uri("https://koma-maven.example.com/")
+ url = uri("https://test.koma-maven.example.com/")
```

これでWorkersからデータを取得できます。
このURLにアクセスすればファイルの一覧が見られるので他のファイルを確認するのも簡単です。

# まとめ

WorkersからR2を扱ってファイル一覧を確認できるようにしました。TypeScriptのコードをもっと工夫すればGradleでのコード例を示したりできると思います。
R2を扱うのにBindingの設定をすこし書くだけなので非常に簡単です。R2への認証も気にしなくていいのでサッと扱うには楽です。

:::note warn
読み書きの使用量については注意してください。
今回コードで使用したlistはClass Aの `ListObjects` の処理にあたります。
Class Aは[無料枠が月100万リクエスト](https://developers.cloudflare.com/r2/pricing/)なので、それを超えないようお気をつけください。
Custom Domainでデプロイしている場合には[Cacheを使用](https://developers.cloudflare.com/workers/runtime-apis/cache/)
できるので、そちらでAPIのアクセス回数を減らすことができます。
:::
