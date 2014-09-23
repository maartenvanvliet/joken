defmodule Joken do
  use Jazz
  @moduledoc """
    Encodes and decodes JSON Web Tokens.

    iex(1)> Joken.encode(%{username: "johndoe"}, "secret", :HS256, %{})
    {:ok,
     "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImpvaG5kb2UifQ.OFY_3SbHl2YaM7Y4Lj24eVMtcDaGEZU7KRzYCV4cqog"}
    iex(2)> Joken.decode("eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VybmFtZSI6ImpvaG5kb2UifQ.OFY_3SbHl2YaM7Y4Lj24eVMtcDaGEZU7KRzYCV4cqog")
    {:ok, %{username: "johndoe"}}
  """

  def encode(payload, key, :HS256, headers) do
    do_encode(payload, key, :HS256, headers)
  end

  def encode(payload, key, :HS384, headers) do
    do_encode(payload, key, :HS384, headers)
  end

  def encode(payload, key, :HS512, headers) do
    do_encode(payload, key, :HS512, headers)
  end

  defp do_encode(payload, key, alg, headers) do
    {_, headerJSON} = Map.merge(%{ alg: to_string(alg), "typ": "JWT"}, headers) |> JSON.encode

    {status, payloadJSON} = JSON.encode(payload)

    case status do
      :error ->
        {:error, "Error encoding map to JSON"}
      :ok ->
        header64 = base64url_encode(headerJSON)
        payload64 = base64url_encode(payloadJSON)
        hash_alg = alg_to_hash_alg(alg)

        signature = :crypto.hmac(hash_alg, key, "#{header64}.#{payload64}")
        signature64 = base64url_encode(signature)

        {:ok, "#{header64}.#{payload64}.#{signature64}"}
    end
  end

  def decode(jwt, key) do
    {status, data} = get_data(jwt)

    case status do
      :error ->
        {status, data}
      :ok ->
        payload = Enum.fetch!(data, 1)
        cond do
          verify(data, key) == false ->
            {:error, "Verification failed"}
          is_expired(payload) == true ->
            {:error, "Token is expired"}
          true ->
            {:ok, payload}
        end
    end

  end

  defp get_data(jwt) do
    values = String.split(jwt, ".")
    if Enum.count(values) != 3 do
      {:error, "Invalid JSON Web Token"}
    else
      decoded_data = Enum.map_reduce(values, 0, fn(x, acc) ->                    
        cond do
          acc < 2 ->
            data = base64url_decode(x)
            {_ , map} = JSON.decode(data, keys: :atoms)
            { map , acc + 1}  
          true ->
            {x, acc + 1}                
        end
      end)
      {decoded, _} = decoded_data
      {:ok, decoded}
    end
  end

  defp verify(data, key) do
    header = Enum.fetch!(data, 0)
    payload = Enum.fetch!(data, 1)
    jwt_signature = Enum.fetch!(data, 2)

    header64 = header |> JSON.encode! |> base64url_encode
    payload64 = payload |> JSON.encode! |> base64url_encode

    hash_alg = header.alg |> String.to_atom |> alg_to_hash_alg
    signature = :crypto.hmac(hash_alg, key, "#{header64}.#{payload64}")

    base64url_encode(signature) == jwt_signature
  end

  defp is_expired(payload) do
    if Map.has_key?(payload, :exp) do
      payload.exp < get_current_time()
    else
      false
    end
  end

  def get_current_time() do
    {mega, secs, _} = :os.timestamp()
    mega * 1000000 + secs
  end

  defp alg_to_hash_alg(alg) do
    case alg do
      :HS256 -> :sha256
      :HS384 -> :sha384
      :HS512 -> :sha512
    end
  end

  defp base64url_encode(data) do
    data
    |> :base64.encode_to_string
    |> to_string
    |> String.replace(~r/[\n\=]/, "")
    |> String.replace(~r/\+/, "-")
    |> String.replace(~r/\//, "_")
  end

  defp base64url_decode(data) do
    base64_bin = String.replace(data, "-", "+") |> String.replace("_", "/")
    base64_bin = base64_bin <> case rem(byte_size(base64_bin),4) do
      2 -> "=="
      3 -> "="
      _ -> ""
    end

    :base64.decode_to_string(base64_bin) |> to_string
  end

end
