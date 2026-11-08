// The recap has its own surface so normal gestures and status messages keep their lifetimes.
const pinnedRecap=document.createElement("button");
pinnedRecap.type="button";
pinnedRecap.id="miku-pinned-recap";
pinnedRecap.hidden=true;
pinnedRecap.title="클릭하면 요약을 닫아요";
const recapText=document.createElement("span");
recapText.className="miku-recap-text";
pinnedRecap.append(recapText);
document.body.append(pinnedRecap);
let inputEpoch=0;
function clearRecap(){
  inputEpoch++;
  pinnedRecap.hidden=true;
  recapText.textContent="";
}
function pinRecap(text,tone){
  document.dispatchEvent(new CustomEvent("miku-spoken-recap",{detail:JSON.stringify({text,tone})}));
  recapText.textContent=text;
  pinnedRecap.hidden=false;
}
pinnedRecap.addEventListener("click",clearRecap);
function promptEdited(event){
  if(event.target.closest(".dsc-composer") && !event.target.closest(".miku-voice") &&
     event.target.closest('textarea,input[type="text"],[contenteditable="true"]'))clearRecap();
}
document.addEventListener("input",promptEdited,true);
document.addEventListener("compositionstart",promptEdited,true);
