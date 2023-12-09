import {Hono} from "hono";
import {html} from "hono/html";
import {FC} from "hono/jsx";

type Bindings = {
    MAVEN_BUCKET: R2Bucket;
};

const app = new Hono<{Bindings: Bindings}>();

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

export default app;
