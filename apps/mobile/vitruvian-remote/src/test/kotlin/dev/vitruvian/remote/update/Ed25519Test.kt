// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

package dev.vitruvian.remote.update

import java.io.File
import java.security.KeyPairGenerator
import java.security.Signature
import java.util.Base64
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class Ed25519Test {
  private fun hex(s: String): ByteArray =
      ByteArray(s.length / 2) { s.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

  // RFC 8032, section 7.1, TEST 1 to TEST 3.
  private val vectors =
      listOf(
          Triple(
              "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
              "",
              "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b",
          ),
          Triple(
              "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
              "72",
              "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00",
          ),
          Triple(
              "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
              "af82",
              "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a",
          ),
      )

  @Test
  fun rfcVectorsVerify() {
    for ((key, message, signature) in vectors) {
      assertTrue(Ed25519.verify(hex(message), hex(signature), hex(key)))
    }
  }

  @Test
  fun anyFlippedBitIsRefused() {
    val (key, message, signature) = vectors[2]
    val sig = hex(signature)
    for (i in sig.indices) {
      val bad = sig.copyOf()
      bad[i] = (bad[i].toInt() xor 0x01).toByte()
      assertFalse("signature byte $i", Ed25519.verify(hex(message), bad, hex(key)))
    }
    assertFalse(Ed25519.verify(byteArrayOf(0xaf.toByte(), 0x83.toByte()), sig, hex(key)))
    val badKey = hex(key).also { it[5] = (it[5].toInt() xor 0x10).toByte() }
    assertFalse(Ed25519.verify(hex(message), sig, badKey))
  }

  @Test
  fun wrongLengthsAndNonCanonicalScalarAreRefused() {
    val (key, message, signature) = vectors[0]
    assertFalse(Ed25519.verify(hex(message), hex(signature).copyOf(63), hex(key)))
    assertFalse(Ed25519.verify(hex(message), hex(signature), hex(key).copyOf(31)))
    // s + q is the same point maths but not the canonical encoding: RFC 8032 says refuse it.
    val sig = hex(signature)
    val s = java.math.BigInteger(1, sig.copyOfRange(32, 64).reversedArray())
    val q =
        java.math.BigInteger.valueOf(2)
            .pow(252)
            .add(java.math.BigInteger("27742317777372353535851937790883648493"))
    val big = s.add(q).toByteArray().reversedArray().copyOf(32)
    assertFalse(Ed25519.verify(hex(message), sig.copyOfRange(0, 32) + big, hex(key)))
  }

  @Test
  fun agreesWithTheJdkOnRandomKeysAndMessages() {
    val random = java.util.Random(7)
    repeat(25) { round ->
      val pair = KeyPairGenerator.getInstance("Ed25519").generateKeyPair()
      val raw = pair.public.encoded.takeLast(32).toByteArray()
      val message = ByteArray(random.nextInt(300)).also(random::nextBytes)
      val signer = Signature.getInstance("Ed25519")
      signer.initSign(pair.private)
      signer.update(message)
      val sig = signer.sign()
      assertTrue("round $round", Ed25519.verify(message, sig, raw))
      if (message.isNotEmpty()) {
        message[0] = (message[0].toInt() xor 0x80).toByte()
        assertFalse("round $round tampered", Ed25519.verify(message, sig, raw))
      }
    }
  }

  /** The real thing: the website's signed tool catalogue, with VitruvianSoftware's public key. */
  @Test
  fun theWebsitesSignedCatalogueVerifiesWithThePinnedKey() {
    val dir = File(System.getenv("TEST_SRCDIR"), System.getenv("TEST_WORKSPACE"))
    val site = File(dir, "apps/web/vitruviansoftware-dev/tools/catalog")
    val data = File(site, "tools.json").readBytes()
    val sig = Base64.getDecoder().decode(File(site, "tools.json.sig").readText().trim())
    val key = Base64.getDecoder().decode(UpdateFeed.PUBLIC_KEY)
    assertTrue(Ed25519.verify(data, sig, key))
    assertFalse(Ed25519.verify(data + byteArrayOf(0x0a), sig, key))
  }
}
