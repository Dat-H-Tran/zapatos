
<a name="0x1_any_alt"></a>

# Module `0x1::any_alt`



-  [Constants](#@Constants_0)
-  [Function `etype_mismatch`](#0x1_any_alt_etype_mismatch)


<pre><code></code></pre>



<a name="@Constants_0"></a>

## Constants


<a name="0x1_any_alt_ETYPE_MISMATCH"></a>

The type provided for <code>unpack</code> is not the same as was given for <code>pack</code>.


<pre><code><b>const</b> <a href="any.md#0x1_any_alt_ETYPE_MISMATCH">ETYPE_MISMATCH</a>: u64 = 1;
</code></pre>



<a name="0x1_any_alt_etype_mismatch"></a>

## Function `etype_mismatch`

The type provided for <code>unpack</code> is not the same as was given for <code>pack</code>.


<pre><code><b>public</b> <b>fun</b> <a href="any.md#0x1_any_alt_etype_mismatch">etype_mismatch</a>(): u64
</code></pre>



<details>
<summary>Implementation</summary>


<pre><code><b>public</b> <b>fun</b> <a href="any.md#0x1_any_alt_etype_mismatch">etype_mismatch</a>(): u64 {
    <b>return</b> <a href="any.md#0x1_any_alt_ETYPE_MISMATCH">ETYPE_MISMATCH</a>
}
</code></pre>



</details>


[move-book]: https://aptos.dev/guides/move-guides/book/SUMMARY
