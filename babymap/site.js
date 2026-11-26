// Keep questions accessible with native <details>; opening one closes the others.
const questions = document.querySelectorAll('.faq-list details');
questions.forEach(question => question.addEventListener('toggle', () => {
  if (question.open) questions.forEach(other => { if (other !== question) other.open = false; });
}));
