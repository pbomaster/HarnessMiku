"""Apply PR 7 GPU changes to the pinned upstream renderer."""
from hashlib import sha256

# Line offsets refer to the exact upstream digest checked below.
EDITS = [
    (3206, 3220, (
        '        this.bindGeometry(bufferData, shaderSet, vertexArray, uvArray, indexArray);\n'
    )),
    (3260, 3274, (
        '        this.bindGeometry(bufferData, shaderSet, vertexArray, uvArray, indexArray);\n'
    )),
    (3290, 3292, (
        '      this.gl.blendFuncSeparate(SRC_COLOR, DST_COLOR, SRC_ALPHA, DST_ALPHA);\n'
        '    }\n'
        '    // LOCAL PATCH: 프레임마다 한 번에 올린 버퍼(dsUploadGeometry)를 offset으로 가리킨다. 다른 메모리 영역이면 원래처럼 그때그때 올린다.\n'
        '    bindGeometry(bufferData, shaderSet, vertexArray, uvArray, indexArray) {\n'
        '      const gl = this.gl;\n'
        '      const shared = bufferData.dsOk && vertexArray.buffer === bufferData.dsV.buf && uvArray.buffer === bufferData.dsUv.buf && indexArray.buffer === bufferData.dsIx.buf;\n'
        '      if (shared) {\n'
        '        gl.bindBuffer(gl.ARRAY_BUFFER, bufferData.dsVBuf);\n'
        '        gl.enableVertexAttribArray(shaderSet.attributePositionLocation);\n'
        '        gl.vertexAttribPointer(shaderSet.attributePositionLocation, 2, gl.FLOAT, false, 0, vertexArray.byteOffset - bufferData.dsV.lo);\n'
        '        gl.bindBuffer(gl.ARRAY_BUFFER, bufferData.dsUvBuf);\n'
        '        gl.enableVertexAttribArray(shaderSet.attributeTexCoordLocation);\n'
        '        gl.vertexAttribPointer(shaderSet.attributeTexCoordLocation, 2, gl.FLOAT, false, 0, uvArray.byteOffset - bufferData.dsUv.lo);\n'
        '        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufferData.dsIxBuf);\n'
        '        bufferData.dsIxOff = indexArray.byteOffset - bufferData.dsIx.lo;\n'
        '        return;\n'
    )),
    (3293, 3296, (
        '      if (bufferData.vertex == null) bufferData.vertex = gl.createBuffer();\n'
        '      gl.bindBuffer(gl.ARRAY_BUFFER, bufferData.vertex);\n'
        '      gl.bufferData(gl.ARRAY_BUFFER, vertexArray, gl.DYNAMIC_DRAW);\n'
        '      gl.enableVertexAttribArray(shaderSet.attributePositionLocation);\n'
        '      gl.vertexAttribPointer(shaderSet.attributePositionLocation, 2, gl.FLOAT, false, 0, 0);\n'
        '      if (bufferData.uv == null) bufferData.uv = gl.createBuffer();\n'
        '      gl.bindBuffer(gl.ARRAY_BUFFER, bufferData.uv);\n'
        '      gl.bufferData(gl.ARRAY_BUFFER, uvArray, gl.DYNAMIC_DRAW);\n'
        '      gl.enableVertexAttribArray(shaderSet.attributeTexCoordLocation);\n'
        '      gl.vertexAttribPointer(shaderSet.attributeTexCoordLocation, 2, gl.FLOAT, false, 0, 0);\n'
        '      if (bufferData.index == null) bufferData.index = gl.createBuffer();\n'
        '      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bufferData.index);\n'
        '      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, indexArray, gl.DYNAMIC_DRAW);\n'
        '      bufferData.dsIxOff = 0;\n'
    )),
    (3508, 3508, (
        '      for (const k of ["dsVBuf", "dsUvBuf", "dsIxBuf"]) if (this._bufferData[k]) { this.gl && this.gl.deleteBuffer(this._bufferData[k]); this._bufferData[k] = null; }\n'
    )),
    (3511, 3511, (
        '    // LOCAL PATCH: Core의 정점·UV·인덱스 배열은 각각 한 메모리 영역에 drawable 순서로 붙어 있다.\n'
        '    // 정점은 프레임마다 한 번에, UV·인덱스는 처음 한 번만 올리고, 그릴 때는 offset으로 가리킨다 (drawable마다 bufferData 3번 → 프레임당 1번).\n'
        '    dsUploadGeometry() {\n'
        '      const gl = this.gl, bd = this._bufferData, d = this.getModel().getModel().drawables;\n'
        '      if (bd.dsOk === false || !d.count) return;\n'
        '      if (!bd.dsV || bd.dsV.buf !== d.vertexPositions[0].buffer) {\n'
        '        const span = (arrs) => {\n'
        '          const buf = arrs[0].buffer; let lo = Infinity, hi = 0;\n'
        '          for (let i = 0; i < d.count; i++) {\n'
        '            const a = arrs[i];\n'
        '            if (a.buffer !== buf) return null;\n'
        '            lo = Math.min(lo, a.byteOffset); hi = Math.max(hi, a.byteOffset + a.byteLength);\n'
        '          }\n'
        '          return { buf, lo, bytes: new Uint8Array(buf, lo, hi - lo) };\n'
        '        };\n'
        '        const v = span(d.vertexPositions), uv = span(d.vertexUvs), ix = span(d.indices);\n'
        '        if (!v || !uv || !ix) { bd.dsOk = false; return; }   // 한 영역이 아니면 원래 방식으로\n'
        '        bd.dsV = v; bd.dsUv = uv; bd.dsIx = ix;\n'
        '        bd.dsVBuf = bd.dsVBuf || gl.createBuffer(); bd.dsUvBuf = bd.dsUvBuf || gl.createBuffer(); bd.dsIxBuf = bd.dsIxBuf || gl.createBuffer();\n'
        '        gl.bindBuffer(gl.ARRAY_BUFFER, bd.dsVBuf); gl.bufferData(gl.ARRAY_BUFFER, v.bytes, gl.DYNAMIC_DRAW);\n'
        '        gl.bindBuffer(gl.ARRAY_BUFFER, bd.dsUvBuf); gl.bufferData(gl.ARRAY_BUFFER, uv.bytes, gl.STATIC_DRAW);\n'
        '        gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, bd.dsIxBuf); gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, ix.bytes, gl.STATIC_DRAW);\n'
        '        bd.dsOk = true;\n'
        '        return;\n'
        '      }\n'
        '      gl.bindBuffer(gl.ARRAY_BUFFER, bd.dsVBuf); gl.bufferSubData(gl.ARRAY_BUFFER, 0, bd.dsV.bytes);\n'
        '    }\n'
    )),
    (3513, 3513, (
        '      this.dsUploadGeometry();\n'
    )),
    (3553, 3554, (
        '      this.gl.drawElements(this.gl.TRIANGLES, indexCount, this.gl.UNSIGNED_SHORT, this._bufferData.dsIxOff || 0);\n'
    )),
]


def patch_renderer(path):
    source = path.read_bytes()
    if sha256(source).hexdigest() != "25ec26bc6337ba9aaf2547dba2996cedd06d0ec930e0fc17492c222fc591959c":
        raise ValueError("Unsupported Cubism renderer")
    lines = source.decode("utf-8").splitlines(keepends=True)
    for start, end, replacement in reversed(EDITS):
        lines[start:end] = [replacement]
    output = "".join(lines).encode("utf-8")
    if sha256(output).hexdigest() != "142116486b7e025836a3a7cf3ea0c6c5a0cdd1e0869b219f2a0b8d7daf5918ae":
        raise ValueError("Renderer patch integrity check failed")
    path.write_bytes(output)
