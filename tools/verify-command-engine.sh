#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
cat > "$scratch/test.c" <<'C'
#include "command.h"
#include <assert.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
typedef struct { unsigned calls, failAt; int shortRead; uint8_t mode;
    struct {uint8_t direction, request, data; uint16_t value, index, length;} sent[1024]; } Mock;
static uint32_t request(void *context,uint8_t direction,uint8_t code,uint16_t value,
                        uint16_t index,uint16_t length,void *data,uint16_t *actual) {
    Mock *m=context; unsigned call=m->calls++;
    assert((value==0 || code==0x21) && call<1024);
    m->sent[call].direction=direction;m->sent[call].request=code;
    m->sent[call].index=index;m->sent[call].length=length;
    m->sent[call].value=value;
    if(direction==0x40)m->sent[call].data=*(uint8_t *)data;
    else {memset(data,0,length);if(code==0x16)*(uint8_t *)data=m->mode;}
    *actual=m->shortRead&&direction==0xc0?0:length;
    return m->failAt==call+1?0xe00002ed:0;
}
static DuetCommand parse(char *name,char *target,char *value) {
    char *args[]={"test",name,target,value,"--apply"};DuetCommand c;
    assert(duet_parse(5,args,&c));return c;
}
int main(void) {
    FILE *out=tmpfile();assert(out);
    DuetCommand gain=parse("--experimental-mic-gain","1","24");
    Mock m={.mode=3};DuetTransport t={.context=&m,.transfer=request};
    assert(duet_execute(&t,&gain,out)==1 && m.calls==1);
    assert(m.sent[0].direction==0xc0 && m.sent[0].request==0x16 && m.sent[0].index==0);
    m=(Mock){.mode=2};assert(duet_execute(&t,&gain,out)==0 && m.calls==2);
    assert(m.sent[1].request==0x34 && m.sent[1].index==1 && m.sent[1].data==24);
    m=(Mock){.mode=2,.shortRead=1};assert(duet_execute(&t,&gain,out)==1 && m.calls==1);
    DuetCommand startup=parse("--experimental-startup-muted","device","1");
    m=(Mock){0};assert(duet_execute(&t,&startup,out)==0 && m.calls==10);
    for(unsigned i=0;i<4;i++) {
        assert(m.sent[i].request==0x35 && m.sent[i].index==i+1 && m.sent[i].data==1);
        assert(m.sent[i+4].request==0x33 && m.sent[i+4].index==i+1 && m.sent[i+4].data==64);
    }
    assert(m.sent[8].request==0xab && m.sent[8].data==0);
    assert(m.sent[9].request==0x25 && m.sent[9].data==1);
    m=(Mock){.failAt=2};assert(duet_execute(&t,&startup,out)==1 && m.calls==2);
    DuetCommand mute=parse("--experimental-output-mute","headphones","1");
    m=(Mock){.failAt=2};assert(duet_execute(&t,&mute,out)==1 && m.calls==2);
    assert(m.sent[0].index==3 && m.sent[1].index==4);
    char *invalid[]={"test","--experimental-routing","outputs","3","--apply"};
    DuetCommand c;assert(!duet_parse(5,invalid,&c));
    invalid[1]="--experimental-mic-gain";invalid[2]="1";invalid[3]="76";
    assert(!duet_parse(5,invalid,&c));
    char *path=getenv("OPENDUET_TEST_FRAME");assert(path);
    DuetCommand display=parse("--experimental-display","device",path);
    DuetDisplayCache cache={0};t.displayCache=&cache;
    m=(Mock){0};assert(duet_execute(&t,&display,out)==0 && m.calls==640);
    assert(m.sent[0].request==0x21 && m.sent[0].value==0 && m.sent[0].index==0x0f07 && m.sent[0].length==64);
    assert(m.sent[636].value==0x9078 && m.sent[636].index==0x9f7f);
    assert(m.sent[639].request==0x22 && m.sent[639].value==0 && m.sent[639].index==0);
    m=(Mock){0};assert(duet_execute(&t,&display,out)==0 && m.calls==0);
    FILE *frame=fopen(path,"r+b");assert(frame);fputc(0x99,frame);fclose(frame);
    m=(Mock){0};assert(duet_execute(&t,&display,out)==0 && m.calls==4);
    frame=fopen(path,"r+b");assert(frame);fputc(0x98,frame);fclose(frame);
    m=(Mock){.failAt=2};assert(duet_execute(&t,&display,out)==1 && m.calls==2 && !cache.valid);
    m=(Mock){0};assert(duet_execute(&t,&display,out)==0 && m.calls==640 && cache.valid);
    fclose(out);puts("Command guard, startup ordering and partial-failure checks passed");
}
C
clang -Wall -Wextra -Werror -I Sources/DuetIdentifier Sources/DuetIdentifier/command.c "$scratch/test.c" -o "$scratch/check"
python3 - "$scratch/frame.rgb565" <<'PY'
import sys
open(sys.argv[1],'wb').write(bytes([0x12,0x34])*160*128)
PY
OPENDUET_TEST_FRAME="$scratch/frame.rgb565" "$scratch/check"
cat > "$scratch/session-test.c" <<'C'
#include "command.h"
#include <string.h>
#include <stdio.h>
static unsigned writes;
static uint32_t request(void *context,uint8_t direction,uint8_t code,uint16_t value,
                        uint16_t index,uint16_t length,void *data,uint16_t *actual) {
    (void)context;(void)value;(void)index;
    if(direction==0x40)++writes;
    else {memset(data,0,length);if(code==0x16)*(uint8_t *)data=2;}
    *actual=length;return 0;
}
int main(void) {setvbuf(stdout,NULL,_IOLBF,0);DuetTransport t={.context=NULL,.transfer=request};
    int result=duet_session(&t);printf("WRITES %u\n",writes);return result;}
C
clang -Wall -Wextra -Werror -I Sources/DuetIdentifier Sources/DuetIdentifier/{command,session}.c "$scratch/session-test.c" -o "$scratch/session-check"
python3 - "$scratch/session-check" <<'PY'
import subprocess,sys
exe=sys.argv[1]
p=subprocess.run([exe],input='QUIT\n',text=True,capture_output=True,timeout=5)
assert p.returncode==0 and 'WRITES 0' in p.stdout,p
p=subprocess.run([exe],input='1 --input-modes\n2 --experimental-mic-gain 1 24 --apply\n3 --experimental-startup-muted device 1 --apply\nQUIT\n',text=True,capture_output=True,timeout=5)
assert p.returncode==0,p
for response in ['END 1 0','END 2 0','END 3 0','WRITES 11']:
 assert response in p.stdout,(response,p.stdout)
p=subprocess.run([exe],input='1 --experimental-routing outputs 3 --apply\nQUIT\n',text=True,capture_output=True,timeout=5)
assert 'END 1 64' in p.stdout and 'WRITES 0' in p.stdout,p.stdout
print('Persistent session framing and no automatic write checks passed')
PY
cp "$scratch/session-check" "$scratch/openduet-identify"
cat > "$scratch/harness.swift" <<'SWIFT'
import Foundation
@main struct Harness {
    static func main() async throws {
        let session = USBSession.shared
        for cycle in 0..<2 {
            let events = try await session.start()
            var connected = false
            var gotMeters = false
            var disconnected = false
            for await event in events {
                switch event {
                case .connected:
                    connected = true
                    if cycle == 1 { try await Task.sleep(for: .milliseconds(1200)) }
                    let modes = await USBHelper.run(["--input-modes"])
                    precondition(modes.exitCode == 0 && modes.output.contains("INPUT_MODES 2 2"))
                    let gain = await USBHelper.run(["--experimental-mic-gain", "1", "24", "--apply"])
                    precondition(gain.exitCode == 0 && gain.output.contains("Request 0x34 index 1"))
                    await session.stop()
                case .meters(let values): gotMeters = values.count == 10
                case .disconnected(let code): precondition(code == 0); disconnected = true
                default: break
                }
            }
            precondition(connected && gotMeters && disconnected)
        }
        print("Swift session command framing, streaming and reconnect checks passed")
    }
}
SWIFT
swiftc -parse-as-library -module-cache-path "$PWD/.build/clang-cache" Sources/OpenDuet/{USBHelper,USBSession,MeterPacket,DeviceEvents}.swift "$scratch/harness.swift" -o "$scratch/swift-session-test"
python3 - "$scratch/swift-session-test" <<'PY'
import subprocess,sys
p=subprocess.run([sys.argv[1]],capture_output=True,text=True,timeout=12)
assert p.returncode==0,(p.stdout,p.stderr)
print(p.stdout.strip())
PY
