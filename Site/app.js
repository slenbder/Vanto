(() => {
  const scenarios = [
    {
      id: 'countdown',
      source: '<span class="source-word" data-word="panic">Panic</span>. <span class="source-word" data-word="plan">Plan</span>. <span class="source-word" data-word="nothing">Nothing</span>. That’s how it goes.',
      targetParts: ['3…\u00a0', '.\u00a02…\u00a0', '.\u00a01…\u00a0', '.\u00a0Go!'],
      slotCase: ['title', 'title', 'title'],
      correctOrder: ['nothing', 'panic', 'plan'],
      hint: 'Three words. Six suspiciously familiar workflows.',
      success: 'Nothing. Panic. Plan. Surprisingly efficient.'
    },
    {
      id: 'suspects',
      source: 'The vase broke. <span class="source-word" data-word="gravity">Gravity</span> did it, <span class="source-word" data-word="my cat">my cat</span> helped, <span class="source-word" data-word="i">I</span> just watched.',
      targetParts: ['', '\u00a0did it,\u00a0', '\u00a0helped, and\u00a0', '\u00a0just watched.'],
      slotCase: ['title', 'lower', 'lower'],
      correctOrder: ['i', 'gravity', 'my cat'],
      hint: 'Same suspects. Very different testimony.',
      success: 'Case closed. The cat was framed.'
    },
    {
      id: 'tagline',
      source: 'One <span class="source-word" data-word="plan">plan</span>. One <span class="source-word" data-word="chance">chance</span>. No <span class="source-word" data-word="backup">backup</span>. That’s the tagline.',
      targetParts: ['One\u00a0', '. One\u00a0', '. No\u00a0', '.'],
      slotCase: ['lower', 'lower', 'lower'],
      correctOrder: ['backup', 'chance', 'plan'],
      hint: 'Rearrange the trailer. Rewrite the movie.',
      success: 'One backup. One chance. No plan. Much more honest.'
    }
  ];

  const chooseScenario = () => {
    let previous = null;
    try { previous = sessionStorage.getItem('vanto-last-scenario'); } catch (_) {}
    const available = previous ? scenarios.filter(scenario => scenario.id !== previous) : [scenarios[0]];
    const chosen = available[Math.floor(Math.random() * available.length)];
    try { sessionStorage.setItem('vanto-last-scenario', chosen.id); } catch (_) {}
    return chosen;
  };

  const scenario = chooseScenario();
  const game = document.querySelector('.word-game');
  const sourceSentence = document.querySelector('.source-sentence');
  const queueList = document.querySelector('.queue-list');
  const queueCount = document.querySelector('.queue-count');
  const queueStatus = document.querySelector('.queue-status');
  const copyButton = document.querySelector('.copy-control');
  const pasteButton = document.querySelector('.paste-control');
  const clearButton = document.querySelector('.clear-control');
  const resetButton = document.querySelector('.reset-control');
  const copyCounter = copyButton.querySelector('small');
  const pasteCounter = pasteButton.querySelector('small');
  const resultHint = document.querySelector('.result-hint');
  const targetSentence = document.querySelector('.target-sentence');
  const previewTargetSentence = document.querySelector('.preview-target-sentence');
  const comingSoonButtons = document.querySelectorAll('[data-coming-soon]');
  const releaseStatus = document.querySelector('.release-status');
  const progressSteps = [...document.querySelectorAll('[data-progress]')];
  const mobileLayout = window.matchMedia('(max-width: 760px)');
  let sourceWords = [];
  let blanks = [];
  let queue = [];
  let copied = 0;
  let pasted = [];
  let draggedIndex = null;
  let pasteInFlight = false;
  let roundEvents = new Set();

  // Demo funnel: each step is reported once per round; Reset starts a new round.
  const trackOnce = (name, data) => {
    if (roundEvents.has(name)) return;
    roundEvents.add(name);
    window.vantoAnalytics?.track(name, data);
  };

  const queueLabel = word => word === 'i' ? 'I' : word;

  const slotLabel = (word, index) => {
    const label = queueLabel(word);
    if (scenario.slotCase[index] === 'title' && word !== 'i') {
      return label.charAt(0).toUpperCase() + label.slice(1);
    }
    return label;
  };

  const setStep = step => {
    game.dataset.step = step;
    const activeStep = step === 'copy' ? 0 : step === 'reorder' || step === 'cleared' ? 1 : 2;
    progressSteps.forEach((item, index) => {
      item.classList.toggle('active', index === activeStep);
      item.classList.toggle('done', index < activeStep);
      if (index === activeStep) item.setAttribute('aria-current', 'step');
      else item.removeAttribute('aria-current');
    });
  };

  const renderTargetTemplate = (container, blankClass) => {
    container.replaceChildren();
    scenario.targetParts.forEach((part, index) => {
      container.appendChild(document.createTextNode(part));
      if (index < 3) {
        const blank = document.createElement('span');
        blank.className = blankClass;
        blank.dataset.index = index;
        blank.textContent = '______';
        container.appendChild(blank);
      }
    });
  };

  const renderScenario = () => {
    sourceSentence.innerHTML = scenario.source;
    sourceWords = [...sourceSentence.querySelectorAll('.source-word')];
    renderTargetTemplate(targetSentence, 'target-blank');
    renderTargetTemplate(previewTargetSentence, 'preview-target-blank');
    blanks = [...targetSentence.querySelectorAll('.target-blank')];
    resultHint.textContent = scenario.hint;
  };

  const flyWord = (label, from, to) => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    const chip = document.createElement('span');
    chip.className = 'flying-word';
    chip.textContent = label;
    chip.style.left = `${from.left}px`;
    chip.style.top = `${from.top}px`;
    document.body.appendChild(chip);
    const dx = to.left - from.left;
    const dy = to.top - from.top;
    chip.animate([
      { transform: 'translate(0, 0) rotate(-2deg) scale(1)', opacity: 1 },
      { transform: `translate(${dx * .52}px, ${dy * .3 - 45}px) rotate(4deg) scale(1.08)`, opacity: 1, offset: .55 },
      { transform: `translate(${dx}px, ${dy}px) rotate(0deg) scale(.84)`, opacity: .1 }
    ], { duration: 560, easing: 'cubic-bezier(.2,.75,.2,1)' }).finished.finally(() => chip.remove());
  };

  const updateControls = () => {
    copyCounter.textContent = `${copied} / 3`;
    pasteCounter.textContent = `${pasted.length} / 3`;
    copyButton.setAttribute('aria-label', `Copy next word, ${copied} of 3 copied`);
    pasteButton.setAttribute('aria-label', `Paste next word, ${pasted.length} of 3 pasted`);
    copyButton.disabled = copied >= sourceWords.length || pasted.length > 0;
    pasteButton.disabled = pasteInFlight || copied < sourceWords.length || queue.length === 0 || pasted.length >= 3;
    clearButton.disabled = queue.length === 0;
    queueCount.textContent = `${queue.length} ${queue.length === 1 ? 'item' : 'items'}`;
  };

  const moveItem = (from, to, method, focusDirection = 0) => {
    if (to < 0 || to >= queue.length || from === to) return;
    const [item] = queue.splice(from, 1);
    queue.splice(to, 0, item);
    trackOnce('Demo Reorder', { method });
    renderQueue();
    queueStatus.textContent = `Moved ${queueLabel(item)} to position ${to + 1}. Meaning pending.`;

    // renderQueue rebuilds every row, so hand keyboard focus back to the moved
    // item's arrow — the opposite one once it reaches the end of the queue.
    if (focusDirection) {
      const [up, down] = queueList.querySelectorAll(`.queue-chip[data-index="${to}"] button`);
      const preferred = focusDirection < 0 ? up : down;
      const fallback = preferred === up ? down : up;
      (preferred.disabled ? fallback : preferred).focus();
    }
  };

  const attachTouchDrag = (chip, grip, index) => {
    let startY = null;
    let currentY = null;
    let rowStep = 0;

    const finishDrag = event => {
      if (startY === null) return;
      const distance = currentY - startY;
      const targetIndex = Math.max(0, Math.min(queue.length - 1, index + Math.round(distance / rowStep)));
      chip.classList.remove('touch-dragging');
      chip.style.transform = '';
      if (grip.hasPointerCapture(event.pointerId)) grip.releasePointerCapture(event.pointerId);
      startY = null;
      currentY = null;
      if (targetIndex !== index) moveItem(index, targetIndex, 'touch');
    };

    grip.addEventListener('pointerdown', event => {
      if (!mobileLayout.matches) return;
      event.preventDefault();
      startY = event.clientY;
      currentY = event.clientY;
      rowStep = chip.getBoundingClientRect().height + 8;
      chip.classList.add('touch-dragging');
      grip.setPointerCapture(event.pointerId);
    });
    grip.addEventListener('pointermove', event => {
      if (startY === null) return;
      event.preventDefault();
      currentY = event.clientY;
      const limit = rowStep * (queue.length - 1);
      const distance = Math.max(-limit, Math.min(limit, currentY - startY));
      chip.style.transform = `translateY(${distance}px) scale(1.015)`;
    });
    grip.addEventListener('pointerup', finishDrag);
    grip.addEventListener('pointercancel', finishDrag);
  };

  const renderQueue = () => {
    if (!queue.length) {
      queueList.innerHTML = '<div class="empty-queue"><span>⌘</span><p>Your copied words will wait here.</p></div>';
      updateControls();
      return;
    }

    queueList.replaceChildren();
    queue.forEach((word, index) => {
      const label = queueLabel(word);
      const chip = document.createElement('div');
      chip.className = 'queue-chip';
      chip.draggable = !mobileLayout.matches;
      chip.dataset.index = index;
      chip.innerHTML = `
        <span class="chip-grip" aria-hidden="true"><svg><use href="#hd-grip"/></svg></span>
        <span class="chip-copy"><small>Text</small><strong>${label}</strong></span>
        <span class="chip-controls">
          <button type="button" data-direction="-1" aria-label="Move ${label} up" ${index === 0 ? 'disabled' : ''}><svg aria-hidden="true"><use href="#hd-up"/></svg></button>
          <button type="button" data-direction="1" aria-label="Move ${label} down" ${index === queue.length - 1 ? 'disabled' : ''}><svg aria-hidden="true"><use href="#hd-down"/></svg></button>
        </span>`;
      chip.addEventListener('dragstart', () => {
        draggedIndex = index;
        chip.classList.add('dragging');
      });
      chip.addEventListener('dragend', () => {
        draggedIndex = null;
        chip.classList.remove('dragging');
      });
      chip.addEventListener('dragover', event => event.preventDefault());
      chip.addEventListener('drop', event => {
        event.preventDefault();
        if (draggedIndex !== null) moveItem(draggedIndex, index, 'drag');
      });
      chip.querySelectorAll('button').forEach(button => {
        const direction = Number(button.dataset.direction);
        button.addEventListener('click', () => moveItem(index, index + direction, 'arrows', direction));
      });
      attachTouchDrag(chip, chip.querySelector('.chip-grip'), index);
      queueList.appendChild(chip);
    });
    updateControls();
  };

  copyButton.addEventListener('click', () => {
    if (copied >= sourceWords.length) return;
    const source = sourceWords[copied];
    const word = source.dataset.word;
    const from = source.getBoundingClientRect();
    const destination = queueList.offsetParent ? queueList : document.querySelector('[data-progress="reorder"]');
    const to = destination.getBoundingClientRect();
    source.classList.add('copied');
    trackOnce('Demo Start', { scenario: scenario.id });
    queue.push(word);
    copied += 1;
    flyWord(queueLabel(word), from, { left: to.left + to.width / 2 - 30, top: to.top + to.height / 2 });
    window.setTimeout(renderQueue, 180);

    if (copied === 3) {
      queueStatus.textContent = 'Right words. New order, new meaning.';
      window.setTimeout(() => setStep('reorder'), 220);
    } else {
      queueStatus.textContent = `${3 - copied} more to copy.`;
    }
    updateControls();
  });

  pasteButton.addEventListener('click', () => {
    if (pasteInFlight || !queue.length || pasted.length >= 3) return;
    pasteInFlight = true;
    const word = queue[0];
    const chip = queueList.querySelector('.queue-chip');
    const from = chip ? chip.getBoundingClientRect() : pasteButton.getBoundingClientRect();

    const completePaste = () => {
      const slotIndex = pasted.length;
      const blank = blanks[slotIndex];
      flyWord(queueLabel(word), from, blank.getBoundingClientRect());
      queue.shift();
      pasted.push(word);
      updateControls();
      window.setTimeout(() => {
        pasteInFlight = false;
        blank.textContent = slotLabel(word, slotIndex);
        blank.classList.add('filled');
        renderQueue();

        if (pasted.length < 3) {
          queueStatus.textContent = `${3 - pasted.length} left to paste.`;
        } else {
          const intendedOrder = pasted.every((value, index) => value === scenario.correctOrder[index]);
          queueStatus.textContent = 'Queue clear. Meaning changed.';
          resultHint.textContent = intendedOrder ? scenario.success : 'Different order. Entirely different story.';
          targetSentence.classList.remove('success');
          void targetSentence.offsetWidth;
          targetSentence.classList.add('success');
          setStep('success');
          trackOnce('Demo Complete', { result: intendedOrder ? 'intended' : 'other' });
        }
      }, 250);
    };

    if (mobileLayout.matches && pasted.length === 0) {
      setStep('paste');
      window.requestAnimationFrame(() => window.requestAnimationFrame(completePaste));
    } else {
      completePaste();
    }
  });

  clearButton.addEventListener('click', () => {
    pasteInFlight = false;
    queue = [];
    if (pasted.length === 0) {
      copied = 0;
      sourceWords.forEach(word => word.classList.remove('copied'));
      queueStatus.textContent = 'Queue cleared. Copy when ready.';
      setStep('copy');
    } else {
      queueStatus.textContent = 'Queue cleared. Reset to start over.';
      setStep('paste');
    }
    renderQueue();
  });

  const resetGame = () => {
    if (roundEvents.size) window.vantoAnalytics?.track('Demo Reset');
    roundEvents = new Set();
    queue = [];
    copied = 0;
    pasted = [];
    pasteInFlight = false;
    sourceWords.forEach(word => word.classList.remove('copied'));
    blanks.forEach(blank => {
      blank.textContent = '______';
      blank.classList.remove('filled');
    });
    resultHint.textContent = scenario.hint;
    targetSentence.classList.remove('success');
    queueStatus.textContent = 'Start with Copy.';
    setStep('copy');
    renderQueue();
  };

  resetButton.addEventListener('click', resetGame);
  comingSoonButtons.forEach(button => button.addEventListener('click', () => {
    releaseStatus.textContent = button.dataset.comingSoonMessage;
  }));
  renderScenario();
  setStep('copy');
  renderQueue();
})();
