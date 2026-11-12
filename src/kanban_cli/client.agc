import HTTP from "std/http"
import Settings from "settings"

export struct Client
  url: String
  key: String
  agent: String
end

export def from(config: Settings.Config) -> Client = Client(url: config.url, key: config.key, agent: config.agent)

export def get(client: Client, path: String) -> Result[HttpResponse] = call(client, "GET", path, "")

export def post(client: Client, path: String, body: String) -> Result[HttpResponse] = call(client, "POST", path, body)

export def patch(client: Client, path: String, body: String) -> Result[HttpResponse]
  call(client, "PATCH", path, body)
end

export def delete(client: Client, path: String) -> Result[HttpResponse] = call(client, "DELETE", path, "")

# Retries a BUSY answer three times (200, 400, 800 ms). A failed write is not
# repeated: the request may have arrived, and only GET is safe to send twice.
export def call(client: Client, method: String, path: String, body: String) -> Result[HttpResponse]
  result = request_once(client, method, path, body)
  for delay in [200, 400, 800]
    if result.ok?
      return result if not busy?(result.unwrap!)
    else
      return result if method != "GET"
    end

    Task.sleep(delay)
    result = request_once(client, method, path, body)
  end

  result
end

def request_once(client: Client, method: String, path: String, body: String) -> Result[HttpResponse]
  handle = try HTTP.client(HttpClientOptions(timeout_ms: 5000))
  result = HTTP.request(handle, method, "#{client.url}#{path}", body.bytes, headers(client, method, body))
  HTTP.close_client(handle)
  result
end

def headers(client: Client, method: String, body: String) -> List[Header]
  fields = [Header(name: "apikey", value: client.key)]
  if method != "GET" and not client.agent.empty?
    fields = fields.push(Header(name: "X-Kanban-Agent", value: client.agent))
  end

  if not body.empty?
    fields = fields.push(Header(name: "Content-Type", value: "application/json"))
  end

  fields
end

def busy?(response: HttpResponse) -> Bool = response.status == 503
