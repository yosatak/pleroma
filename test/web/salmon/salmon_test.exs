defmodule Pleroma.Web.Salmon.SalmonTest do
  use Pleroma.DataCase
  alias Pleroma.Web.Salmon
  alias Pleroma.{Repo, Activity, User}
  import Pleroma.Factory

  @magickey "RSA.pu0s-halox4tu7wmES1FVSx6u-4wc0YrUFXcqWXZG4-27UmbCOpMQftRCldNRfyA-qLbz-eqiwQhh-1EwUvjsD4cYbAHNGHwTvDOyx5AKthQUP44ykPv7kjKGh3DWKySJvcs9tlUG87hlo7AvnMo9pwRS_Zz2CacQ-MKaXyDepk=.AQAB"

  @wrong_magickey "RSA.pu0s-halox4tu7wmES1FVSx6u-4wc0YrUFXcqWXZG4-27UmbCOpMQftRCldNRfyA-qLbz-eqiwQhh-1EwUvjsD4cYbAHNGHwTvDOyx5AKthQUP44ykPv7kjKGh3DWKySJvcs9tlUG87hlo7AvnMo9pwRS_Zz2CacQ-MKaXyDepk=.AQAA"

  @magickey_friendica "RSA.AMwa8FUs2fWEjX0xN7yRQgegQffhBpuKNC6fa5VNSVorFjGZhRrlPMn7TQOeihlc9lBz2OsHlIedbYn2uJ7yCs0.AQAB"

  test "decodes a salmon" do
    {:ok, salmon} = File.read("test/fixtures/salmon.xml")
    {:ok, doc} = Salmon.decode_and_validate(@magickey, salmon)
    assert Regex.match?(~r/xml/, doc)
  end

  test "errors on wrong magic key" do
    {:ok, salmon} = File.read("test/fixtures/salmon.xml")
    assert Salmon.decode_and_validate(@wrong_magickey, salmon) == :error
  end

  test "generates an RSA private key pem" do
    {:ok, key} = Salmon.generate_rsa_pem()
    assert is_binary(key)
    assert Regex.match?(~r/RSA/, key)
  end

  test "it encodes a magic key from a public key" do
    key = Salmon.decode_key(@magickey)
    magic_key = Salmon.encode_key(key)

    assert @magickey == magic_key
  end

  test "it decodes a friendica public key" do
    _key = Salmon.decode_key(@magickey_friendica)
  end

  test "returns a public and private key from a pem" do
    pem = File.read!("test/fixtures/private_key.pem")
    {:ok, private, public} = Salmon.keys_from_pem(pem)

    assert elem(private, 0) == :RSAPrivateKey
    assert elem(public, 0) == :RSAPublicKey
  end

  test "encodes an xml payload with a private key" do
    doc = File.read!("test/fixtures/incoming_note_activity.xml")
    pem = File.read!("test/fixtures/private_key.pem")
    {:ok, private, public} = Salmon.keys_from_pem(pem)

    # Let's try a roundtrip.
    {:ok, salmon} = Salmon.encode(private, doc)
    {:ok, decoded_doc} = Salmon.decode_and_validate(Salmon.encode_key(public), salmon)

    assert doc == decoded_doc
  end

  test "it gets a magic key" do
    salmon = File.read!("test/fixtures/salmon2.xml")
    {:ok, key} = Salmon.fetch_magic_key(salmon)

    assert key ==
             "RSA.uzg6r1peZU0vXGADWxGJ0PE34WvmhjUmydbX5YYdOiXfODVLwCMi1umGoqUDm-mRu4vNEdFBVJU1CpFA7dKzWgIsqsa501i2XqElmEveXRLvNRWFB6nG03Q5OUY2as8eE54BJm0p20GkMfIJGwP6TSFb-ICp3QjzbatuSPJ6xCE=.AQAB"
  end

  test "it pushes an activity to remote accounts it's addressed to" do
    user_data = %{
      info: %{
        "salmon" => "http://example.org/salmon"
      },
      local: false
    }

    mentioned_user = insert(:user, user_data)
    note = insert(:note)

    activity_data = %{
      "id" => Pleroma.Web.ActivityPub.Utils.generate_activity_id(),
      "type" => "Create",
      "actor" => note.data["actor"],
      "to" => note.data["to"] ++ [mentioned_user.ap_id],
      "object" => note.data,
      "published_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "context" => note.data["context"]
    }

    {:ok, activity} = Repo.insert(%Activity{data: activity_data, recipients: activity_data["to"]})
    user = Repo.get_by(User, ap_id: activity.data["actor"])
    {:ok, user} = Pleroma.Web.WebFinger.ensure_keys_present(user)

    poster = fn url, _data, _headers, _options ->
      assert url == "http://example.org/salmon"
    end

    Salmon.publish(user, activity, poster)
  end
end
