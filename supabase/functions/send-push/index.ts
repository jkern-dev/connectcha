// send-push: placeholder until its milestone. Returns 501 so nothing can mistake it for a working endpoint.
Deno.serve(() => new Response(JSON.stringify({ error: "not_implemented" }), { status: 501, headers: { "content-type": "application/json" } }));
